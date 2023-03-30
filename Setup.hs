{-# LANGUAGE NamedFieldPuns #-}

import Control.Monad (when, unless)
import Data.Char (toLower)
import Data.List (intercalate, intersperse, isPrefixOf, isSuffixOf, stripPrefix)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Maybe (fromMaybe)
import Distribution.PackageDescription (ComponentName (..), ForeignLib (..), PackageDescription (..), showComponentName, unUnqualComponentName, unPackageName)
import Distribution.Pretty (Pretty (..))
import Distribution.Simple (PackageIdentifier (..), UserHooks (..), defaultMainWithHooks, simpleUserHooks, versionNumbers)
import Distribution.Simple.LocalBuildInfo (ComponentLocalBuildInfo, LocalBuildInfo (..), componentBuildDir)
import Distribution.Simple.Program (ConfiguredProgram (..), Program, ProgramDb, requireProgram, runDbProgram, runProgram, simpleProgram, getDbProgramOutput, needProgram)
import Distribution.Simple.Setup (BuildFlags (..), fromFlagOrDefault)
import Distribution.Simple.Utils (die', findFirstFile)
import Distribution.Utils.Path (getSymbolicPath)
import Distribution.Utils.ShortText (fromShortText)
import Distribution.Verbosity (Verbosity, normal)
import System.Directory (getDirectoryContents)
import System.FilePath ((<.>), (</>))
import System.Info (os)
import Text.PrettyPrint (render)

type PythonPackageName = FilePath

type HaskellLibraryName = String

pythonProgram :: Program
pythonProgram = simpleProgram "python"

pipxProgram :: Program
pipxProgram = simpleProgram "pipx"

main :: IO ()
main =
  defaultMainWithHooks
    simpleUserHooks
      { hookedPrograms = [pythonProgram, pipxProgram],
        -- Generates a Python package
        postBuild = \args buildFlags packageDescription localBuildInfo -> do
          let verbosity = fromFlagOrDefault normal (buildVerbosity buildFlags)

          -- Get package information
          let PackageDescription {package, author, maintainer, description, licenseRaw} = packageDescription
          let PackageIdentifier {pkgName, pkgVersion} = package
          let packageName = unPackageName pkgName
          let license = render $ either pretty pretty licenseRaw
          let version = intercalate "." (map show (versionNumbers pkgVersion))

          -- Get build information
          (foreignLibName, foreignLibDir) <- findForeignLibInfo verbosity packageDescription localBuildInfo
          let LocalBuildInfo {withPrograms} = localBuildInfo

          -- Create pyproject.toml
          writeFile "pyproject.toml" (pyprojectTomlTemplate packageName version (fromShortText author) (fromShortText maintainer) (fromShortText description) license)
          -- Create build.py
          writeFile "build.py" (buildPyTemplate packageName foreignLibName foreignLibDir)
          -- Build the wheel:
          pipx verbosity withPrograms ["run", "--spec", "build", "pyproject-build", "--wheel"]
          -- Check the wheel:
          pipx verbosity withPrograms ["run", "twine", "check", "dist/*.whl"]
      }

python :: Verbosity -> ProgramDb -> [String] -> IO ()
python verbosity = runDbProgram verbosity pythonProgram

pipx :: Verbosity -> ProgramDb -> [String] -> IO ()
pipx verbosity programDb args = do
  maybePipxProgram <- needProgram verbosity pipxProgram programDb
  case maybePipxProgram of
    Nothing -> do
      pipxExists <- doesPipxExist verbosity programDb
      unless pipxExists . die' verbosity $
        "The program 'pipx' is required but it could not be found."
      runDbProgram verbosity pythonProgram programDb ("-m" : "pipx" : args)
    Just (pipxProgram, programDb) -> do
      runProgram verbosity pipxProgram args

doesPipxExist :: Verbosity -> ProgramDb -> IO Bool
doesPipxExist verbosity programDb = do
  output <- getDbProgramOutput verbosity pythonProgram programDb
    ["-c", "import importlib.util; print(importlib.util.find_spec('pipx') is not None)"]
  return $ output == "True"

pyprojectTomlTemplate :: String -> String -> String -> String -> String -> String -> String
pyprojectTomlTemplate packageName version authorName authorEmail description license =
  unlines
    [ "[build-system]",
      "requires = ['poetry-core>=1.5.0', 'delocate; platform_system==\"Darwin\"']",
      "build-backend = 'poetry.core.masonry.api'",
      "",
      "[tool.poetry]",
      "name = '" <> packageName <> "'",
      "version = '" <> version <> "'",
      "authors = ['" <> authorName <> " <" <> authorEmail <> ">']",
      "description = '" <> description <> "'",
      "readme = 'README.md'",
      "license = '" <> license <> "'",
      "include = [",
      "  # Build script must be included in the sdist",
      "  { path = 'build.py', format = 'sdist' },",
      "  # C extensions must be included in the wheel",
      "  { path = '" <> packageName <> "/*.so', format = 'wheel' },",
      "  { path = '" <> packageName <> "/*.dylib', format = 'wheel' },",
      "  { path = '" <> packageName <> "/*.pyd', format = 'wheel' },",
      "]",
      "",
      "[tool.poetry.build]",
      "script = 'build.py'",
      "generate-setup-file = false",
      "",
      "[tool.poetry.scripts]",
      "fib = 'fib:main'"
    ]

buildPyTemplate :: String -> String -> String -> String
buildPyTemplate packageName foreignLibName foreignLibDir =
  unlines
    [ "from distutils.command.build_ext import build_ext",
      "from distutils.core import Distribution, Extension",
      "import os",
      "import platform",
      "import shutil",
      "",
      "ext_modules = [",
      "    Extension(",
      "        name='" <> packageName <> "._binding',",
      "        libraries=['" <> foreignLibName <> "'],",
      "        library_dirs=['" <> foreignLibDir <> "'],",
      "        sources=['./" <> packageName <> "/binding.i'],",
      "    )",
      "]",
      "",
      "",
      "def build():",
      "    distribution = Distribution({",
      "      'name': '" <> packageName <> "',",
      "      'ext_modules': ext_modules",
      "})",
      "    distribution.package_dir = '" <> packageName <> "'",
      "",
      "    cmd = build_ext(distribution)",
      "    cmd.ensure_finalized()",
      "    cmd.run()",
      "",
      "    # Copy built extensions back to the project",
      "    for output in cmd.get_outputs():",
      "        relative_extension = os.path.relpath(output, cmd.build_lib)",
      "        shutil.copyfile(output, relative_extension)",
      "        mode = os.stat(relative_extension).st_mode",
      "        mode |= (mode & 0o444) >> 2",
      "        os.chmod(relative_extension, mode)",
      "",
      "    # Workaround for issue with RPATH on macOS",
      "    # See: https://github.com/pypa/cibuildwheel/issues/816",
      "    if platform.system() == 'Darwin':",
      "        os.environ['DYLD_LIBRARY_PATH'] = '"<> foreignLibDir <>"'",
      "        import delocate",
      "        delocate.delocate_path('"<> packageName <>"', '"<> packageName <>"')",
      "",
      "if __name__ == '__main__':",
      "    build()",
      ""
    ]

findForeignLibInfo :: Verbosity -> PackageDescription -> LocalBuildInfo -> IO (HaskellLibraryName, FilePath)
findForeignLibInfo verbosity packageDescription localBuildInfo = do
  let PackageDescription {foreignLibs} = packageDescription
  when (length foreignLibs /= 1) $
    die' verbosity "Could not find unique foreign library"
  let [ForeignLib {foreignLibName}] = foreignLibs
  let LocalBuildInfo {componentNameMap} = localBuildInfo
  let componentLocalBuildInfos = componentNameMap Map.! CFLibName foreignLibName
  when (length componentLocalBuildInfos /= 1) $
    die' verbosity "Could not find unique foreign libraries component"
  let [componentLocalBuildInfo] = componentLocalBuildInfos
  return (unUnqualComponentName foreignLibName, componentBuildDir localBuildInfo componentLocalBuildInfo)
