# Kubernetes CA Certificate Rotation Scripts

This directory contains a set of scripts to perform a safe, phased CA certificate rotation for a Kubernetes cluster. The process is designed to be executed from a bastion host with SSH access to all cluster nodes.

## Overall Process

The rotation follows a best-practice methodology to avoid cluster downtime by establishing a temporary state of dual-CA trust.

1.  **Preparation (`01-prepare.sh`)**: Backs up existing cluster certificates, generates a new set of CAs and leaf certificates, and creates a temporary "bundle" configuration that trusts both the old and new CAs.
2.  **Establish Dual Trust (`02-apply-bundle.sh`)**: Rolls out the "bundle" configuration to all nodes. After this step, the cluster can validate certificates signed by either the old or the new CA.
3.  **Deploy New Leaf Certificates (`03-apply-new-certs.sh`)**: With dual trust established, this step safely replaces all component (apiserver, etcd, etc.) certificates with the new ones.
4.  **Finalize the Switch (`04-apply-final-config.sh`)**: Removes the old CA from the trust stores, completing the migration to the new certificate authority.

## Emergency Rollback

The `rollback.sh` script provides a disaster recovery mechanism. It can be run at any point during the process to revert the cluster's configuration to the initial state captured during the preparation step.

## Usage

The scripts should be executed in numerical order: `01` -> `02` -> `03` -> `04`. The `00-config.sh` file must be configured with the correct environment details before starting.
