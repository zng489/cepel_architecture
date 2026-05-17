import yaml
from metadata.workflow.metadata import MetadataWorkflow

def run():
    with open("/tmp/iceberg-polaris.yaml", "r") as f:
        workflow_config = yaml.safe_load(f)
    workflow = MetadataWorkflow.create(workflow_config)
    workflow.execute()
    workflow.raise_from_status()
    workflow.print_status()
    workflow.stop()

if __name__ == "__main__":
    run()