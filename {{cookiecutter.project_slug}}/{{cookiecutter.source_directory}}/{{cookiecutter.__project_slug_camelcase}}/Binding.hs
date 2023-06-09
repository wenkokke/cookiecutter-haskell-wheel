{-# LANGUAGE ForeignFunctionInterface #-}
{-# OPTIONS_GHC -Wall #-}

module {{cookiecutter.__project_slug_camelcase}}.Binding where

import Control.Monad (forM_)
import Data.Version (showVersion)
import Foreign.C.String (CString, newCString)
import Paths_{{cookiecutter.__project_slug_snakecase}} (version)
import System.Environment (getArgs)
import Text.Read (readMaybe)

foreign export ccall hs_{{cookiecutter.__project_slug_snakecase}}_version :: IO CString

hs_{{cookiecutter.__project_slug_snakecase}}_version :: IO CString
hs_{{cookiecutter.__project_slug_snakecase}}_version =
  newCString (showVersion version)

foreign export ccall hs_{{cookiecutter.__project_slug_snakecase}}_main :: IO ()

hs_{{cookiecutter.__project_slug_snakecase}}_main :: IO ()
hs_{{cookiecutter.__project_slug_snakecase}}_main =
  getArgs >>= \args ->
    forM_ args $ \arg -> do
      case readMaybe arg of
        Just n  -> putStrLn $ "fib " <> show n <> " -> " <> show (fib n)
        Nothing -> putStrLn $ "fib " <> arg    <> " -> error"

-- Taken from:
-- https://wiki.haskell.org/The_Fibonacci_sequence#Fastest_Fib_in_the_West
fib :: Integer -> Integer
fib n = snd . foldl fib_ (1, 0) . map (toEnum . fromIntegral) $ unfoldl divs n
  where
    unfoldl :: (Integer -> Maybe (Integer, Integer)) -> Integer -> [Integer]
    unfoldl f x = case f x of
      Nothing -> []
      Just (u, v) -> unfoldl f v ++ [u]

    divs :: Integer -> Maybe (Integer, Integer)
    divs 0 = Nothing
    divs k = Just (uncurry (flip (,)) (k `divMod` 2))

    fib_ :: (Integer, Integer) -> Bool -> (Integer, Integer)
    fib_ (f, g) p
      | p = (f * (f + 2 * g), f `pow` 2 + g `pow` 2)
      | otherwise = (f `pow` 2 + g `pow` 2, g * (2 * f - g))

    pow :: Integer -> Integer -> Integer
    pow = (^)
