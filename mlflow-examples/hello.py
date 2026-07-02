"""
Demonstrates how to log parameters, metrics, and artifacts to an MLFlow experiment.
"""

from random import random

import mlflow


def main():
    mlflow.log_param("hello_param", "world")
    mlflow.log_metric("hello_metric", random())
    with open("hello.txt", "w") as f:
        f.write("Hello, world!")
    mlflow.log_artifact("hello.txt")


if __name__ == "__main__":
    mlflow.set_workspace("examples")  # e.g. project name
    mlflow.set_experiment("hello-world")
    with mlflow.start_run() as run:
        main()
