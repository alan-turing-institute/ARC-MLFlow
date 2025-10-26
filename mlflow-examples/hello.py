from random import random

import mlflow


def main():
    mlflow.log_param("hello_param", "world")
    mlflow.log_metric("hello_metric", random())
    with open("hello.txt", "w") as f:
        f.write("Hello, world!")
    mlflow.log_artifact("hello.txt")


if __name__ == "__main__":
    mlflow.set_tracking_uri("http://0.0.0.0:5000")
    experiment_name = "hello-world-example"
    mlflow.set_experiment(experiment_name)
    with mlflow.start_run() as run:
        main()
