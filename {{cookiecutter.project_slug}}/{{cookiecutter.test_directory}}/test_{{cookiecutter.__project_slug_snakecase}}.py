from typing import List


def test_{{cookiecutter.__project_slug_snakecase}}_version() -> None:
    import {{cookiecutter.__project_slug_snakecase}}

    assert {{cookiecutter.__project_slug_snakecase}}.version() == {{cookiecutter.__project_slug_snakecase}}.VERSION


def assert_{{cookiecutter.__project_slug_snakecase}}_main(args: List[str], golden_output: str) -> None:
    import subprocess

    actual_output = (
        subprocess.check_output(["{{cookiecutter.project_slug}}", *args])
        .decode("utf-8")
        .strip()
    )
    assert actual_output == golden_output


def test_{{cookiecutter.__project_slug_snakecase}}_main() -> None:
    assert_{{cookiecutter.__project_slug_snakecase}}_main(["11"], "fib 11 -> 89")
    assert_{{cookiecutter.__project_slug_snakecase}}_main(["23"], "fib 23 -> 28657")
    assert_{{cookiecutter.__project_slug_snakecase}}_main(["35"], "fib 35 -> 9227465")
    assert_{{cookiecutter.__project_slug_snakecase}}_main(["47"], "fib 47 -> 2971215073")
    assert_{{cookiecutter.__project_slug_snakecase}}_main(["59"], "fib 59 -> 956722026041")
