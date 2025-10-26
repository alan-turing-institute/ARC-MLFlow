import mlflow
import numpy as np
from datasets import load_dataset
from hyperopt import STATUS_OK, Trials, fmin, hp, tpe
from transformers import (
    DataCollatorWithPadding,
    DebertaV2ForSequenceClassification,
    DebertaV2Tokenizer,
    Trainer,
    TrainingArguments,
)


def optimize(params):
    with mlflow.start_run(nested=True):
        mlflow.log_params(params)

        hf_dataset_path = "sonos-nlu-benchmark/snips_built_in_intents"
        dataset = load_dataset(hf_dataset_path, split="train")
        splits = dataset.train_test_split(test_size=0.2)
        train_dataset = splits["train"]
        eval_dataset = splits["test"]

        hf_model_path = "microsoft/deberta-v3-xsmall"
        tokenizer = DebertaV2Tokenizer.from_pretrained(hf_model_path)
        model = DebertaV2ForSequenceClassification.from_pretrained(
            hf_model_path,
            num_labels=train_dataset.features["label"].num_classes,
            id2label={
                i: label
                for i, label in enumerate(train_dataset.features["label"].names)
            },
            label2id={
                label: i
                for i, label in enumerate(train_dataset.features["label"].names)
            },
            ignore_mismatched_sizes=True,
        )

        def preprocess_function(examples):
            return tokenizer(examples["text"], truncation=True)

        train_dataset = train_dataset.map(preprocess_function, batched=True)
        eval_dataset = eval_dataset.map(preprocess_function, batched=True)
        collator = DataCollatorWithPadding(tokenizer=tokenizer)

        training_args = TrainingArguments(
            "tmp",
            report_to="mlflow",
            eval_strategy="epoch",
            save_strategy="no",
            logging_strategy="steps",
            logging_steps=0.01,
            **params,
        )

        trainer = Trainer(
            model=model,
            args=training_args,
            train_dataset=train_dataset,
            eval_dataset=eval_dataset,
            data_collator=collator,
            processing_class=tokenizer,
        )
        trainer.train()

        return {"loss": trainer.evaluate()["eval_loss"], "status": STATUS_OK}


if __name__ == "__main__":
    mlflow.set_experiment("test-sweep")
    mlflow.enable_system_metrics_logging()
    search_space = {
        "learning_rate": hp.loguniform("learning_rate", np.log(1e-5), np.log(1e-1)),
    }
    with mlflow.start_run(run_name="sweep-snips"):
        trials = Trials()
        best_params = fmin(
            fn=optimize,
            space=search_space,
            algo=tpe.suggest,
            max_evals=15,
            trials=trials,
            verbose=True,
        )
        print("best", best_params)
        # Find and log best results
        best_trial = min(trials.results, key=lambda x: x["loss"])
        best_loss = best_trial["loss"]

        # Log optimization results
        mlflow.log_params(
            {
                "best_learning_rate": best_params["learning_rate"],
            }
        )
        mlflow.log_metrics(
            {
                "best_val_loss": best_loss,
                "total_trials": len(trials.trials),
                "optimization_completed": 1,
            }
        )
