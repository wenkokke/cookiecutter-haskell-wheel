from typing import List

from ._binding import (
    unsafe_hs_{{cookiecutter.__project_slug_snakecase}}_version,
    unsafe_hs_{{cookiecutter.__project_slug_snakecase}}_main,
    unsafe_hs_init,
    unsafe_hs_exit,
)

VERSION: str = "{{cookiecutter.version}}"


def version() -> str:
    try:
        unsafe_hs_init([])
        return str(unsafe_hs_{{cookiecutter.__project_slug_snakecase}}_version())
    finally:
        unsafe_hs_exit()


def main(args: List[str]) -> None:
    try:
        unsafe_hs_init(args)
        unsafe_hs_{{cookiecutter.__project_slug_snakecase}}_main()
    finally:
        unsafe_hs_exit()
