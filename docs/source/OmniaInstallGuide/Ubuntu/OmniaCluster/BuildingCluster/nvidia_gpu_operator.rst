NVIDIA GPU Operator
=====================

Kubernetes provides access to special hardware resources such as NVIDIA GPUs, NICs, Infiniband adapters and other devices through the device plugin framework.
However, configuring and managing nodes with these hardware resources requires configuration of multiple software components such as drivers, container runtimes or other libraries which are difficult and prone to errors.
The NVIDIA GPU Operator uses the operator framework within Kubernetes to automate the management of all NVIDIA software components needed to provision GPU.
These components include the NVIDIA drivers (to enable CUDA), Kubernetes device plugin for GPUs, the NVIDIA Container Toolkit, automatic node labelling using GFD, DCGM based monitoring and others. To know more, `click here <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/index.html>`_.

Prerequisite
---------------

Ensure that the ``input/software_config.json`` file contains the following line under ``softwares``: ::

    {"name": "nvidia_gpu_operator", "version":"25.3.0"}

A sample version of the ``input/software_config.json`` is located `here <../../../samplefiles.html>`_.

.. note:: Currently, Omnia only supports the ``25.3.0`` version of the NVIDIA GPU operator.

Configurations
----------------

Omnia installs the NVIDIA GPU operator as part of ``omnia.yml`` or ``scheduler.yml`` playbook execution, based on if the ``input/omnia_config.yml`` file contains the required inputs.
Follow the below provided steps to set up the NVIDIA GPU operator for your cluster:

1. Edit the ``nvidia_gpu_operator_config.yml`` file present in the ``omnia/input/`` folder. Provide inputs to the following mandatory parameters in that file:

        * ``http_proxy``: This value can be found in the ``/opt/omnia/offline/local_repo_access.yml`` file.
        * ``https_proxy``: This value can be found in the ``/opt/omnia/offline/local_repo_access.yml`` file.

.. note:: Omnia supports the successful deployment of the NVIDIA GPU Operator for the pre-filled basic configuration, under ``input/nvidia_gpu_operator``. For a more customized installation, the configuration file can be edited as per the user's requirements. However, users must check and verify the compatibility of supported tools and driver versions before proceeding. Omnia does not claim responsibility for any issues arising from custom modifications or compatibility checks.

2. Once the ``nvidia_gpu_operator_config.yml`` file is ready, by default the filepath is added to the ``nvidia_gpu_operator_value_file_path`` parameter in ``input/omnia_config.yml`` file.

Playbook execution
--------------------

Once the above mentioned configurations are done, execute the ``omnia.yml`` or ``scheduler.yml`` playbook to install the NVIDIA GPU operator:

    ::

        cd omnia
        ansible-playbook omnia.yml -i <inventory filepath>

    ::

        cd scheduler
        ansible-playbook scheduler.yml -i <inventory filepath>

Here, the ``<inventory filepath>`` refers to the Kubernetes inventory.

Remove the NVIDIA GPU operator
-----------------------------------

If you want to uninstall the NVIDIA GPU operator, run the following command: ::

    helm delete gpu-operator -n gpu-operator