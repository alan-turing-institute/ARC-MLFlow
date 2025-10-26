import mlflow
from datasets import load_dataset
from transformers import (
    DataCollatorWithPadding,
    DebertaV2ForSequenceClassification,
    DebertaV2Tokenizer,
    Trainer,
    TrainingArguments,
)


def main():
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
            i: label for i, label in enumerate(train_dataset.features["label"].names)
        },
        label2id={
            label: i for i, label in enumerate(train_dataset.features["label"].names)
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
        logging_steps=0.001,
        num_train_epochs=10,
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

    mlflow.transformers.log_model(
        transformers_model={"model": trainer.model, "tokenizer": tokenizer},
        artifact_path="model",
    )


if __name__ == "__main__":
    mlflow.set_experiment("test-hf-trainer")
    mlflow.enable_system_metrics_logging()
    with mlflow.start_run():
        main()
