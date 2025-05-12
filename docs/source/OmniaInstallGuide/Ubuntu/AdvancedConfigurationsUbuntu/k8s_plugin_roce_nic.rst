Kubernetes plugin for RoCE NIC
===================================

.. caution:: Kubernetes plugin for the RoCE NIC is only supported on the Ubuntu clusters (not on RHEL/Rocky Linux clusters).

Few important things to keep in mind before proceeding with the installation:

1. Defined network interfaces with their respective IP ranges (start and end) should be assigned.
2. Number of entries in the ``input/roce_plugin_config.yml`` should be equal to number of RoCE interfaces available in the RoCE pod.
3. VLAN NICs are not supported.
4. This playbook supports the deployment of up to 8 RoCE NIC interfaces.
5. In a scenario where there are two nodes with two separate NICs, the admin must ensure to use aliasing to make the NIC names similar before executing ``deploy_roce_plugin.yml``.
6. Omnia does not validate any parameter entries in the ``input/roce_plugin_config.yml``. It is the user's responsibility to provide correct inputs for the required parameters. In case of any errors encountered due to incorrect entries, delete and re-install the plugin with the correct inputs. For more information, `click here <../../../Troubleshooting/FAQ/Ubuntu/Provision.html>`_.

Install the plugin
-------------------

**Prerequisites**

* Ensure Kubernetes is set up on the cluster with ``flannel`` or ``calico`` as the input for the ``k8s_cni`` parameter present in ``input/omnia_config.yml``. For the complete list of parameters, `click here <../OmniaCluster/schedulerinputparams.html#id12>`_.
* Ensure that the Broadcom RoCE drivers are installed on the nodes.
* Ensure that additional NICs have been configured using the ``server_spec_update.yml`` playbook. For more information on how to configure additional NICs, `click here <../../../Utils/AdditionalNIC.html>`_.
* Ensure that the ``{"name": "roce_plugin"}`` entry is present in the ``software_config.json`` and the same config has been used while executing the ``local_repo.yml`` playbook.
* Ensure to update the below mentioned parameters in ``input/roce_plugin_config.yml``:

.. csv-table:: Parameters for RoCE NIC
   :file: ../../../Tables/roce_config.csv
   :header-rows: 1
   :keepspace:


Here is an example of the ``input/roce_plugin_config.yml``: ::

          interfaces:
            - name: eth1
              range: 192.168.1.0/24
              range_start:
              range_end:
              gateway: 192.168.1.1
              route: 192.168.1.0/24
            - name: eth2
              range: 192.168.2.0/24
              range_start:
              range_end:
              gateway:
              route:
            - name: eth3
              range: 192.168.3.0/24
              range_start:
              range_end:
              gateway:
              route:
            - name: eth4
              range: 192.168.4.0/24
              range_start:
              range_end:
              gateway:
              route:
            - name: eth5
              range: 192.168.5.0/24
              range_start:
              range_end:
              gateway:
              route:
            - name: eth6
              range: 192.168.6.0/24
              range_start:
              range_end:
              gateway:
              route:
            - name: eth7
              range: 192.168.7.0/24
              range_start:
              range_end:
              gateway:
              route:
            - name: eth8
              range: 192.168.8.0/24
              range_start:
              range_end:
              gateway:
              route:

**To install the plugin, run the** ``deploy_roce_plugin.yml`` **playbook**

Run the playbook using the following command: ::

    cd omnia/scheduler
    ansible-playbook deploy_roce_plugin.yml -i inventory

Where the inventory should be the same as the one used to setup Kubernetes on the cluster.

.. note:: A config file named ``roce_plugin.json`` is located in ``omnia\input\config\ubuntu\<os version>\``. This config file contains all the details about the Kubernetes plugin for the RoCE NIC. Here is an example of the config file:
    ::

        {
            "roce_plugin": {
              "cluster": [
              {
                "package": "k8s-rdma-shared-dev-plugin",
                "url": "https://github.com/Mellanox/k8s-rdma-shared-dev-plugin.git",
                "type": "git",
                "version": "v1.5.2"
              },
              {
                "package": "ghcr.io/k8snetworkplumbingwg/multus-cni",
                "tag": "v4.1.4-thick",
                "type": "image"
              },
              {
                "package": "ghcr.io/k8snetworkplumbingwg/whereabouts",
                "tag": "v0.8.0",
                "type": "image"
              },
              {
                "package": "ghcr.io/mellanox/k8s-rdma-shared-dev-plugin",
                "tag": "v1.5.2",
                "type": "image"
              },
              {
                "package": "docker.io/roman8rcm/roce-test",
                "tag": "229.2.32.0",
                "type": "image"
              }
              ]
            }
        }

.. caution:: After running the ``deploy_roce_plugin.yml`` playbook, the RDMA pods will be in ``CrashLoopBackOff`` state and the RoCE pods will be in ``pending`` state. This is a known issue and the resolution can be found `here <../../../Troubleshooting/KnownIssues/Ubuntu/Kubernetes.html>`_.

Delete the plugin
------------------

To delete the plugin, run the ``delete_roce_plugin.yml`` playbook using the following command: ::

    cd omnia/scheduler
    ansible-playbook delete_roce_plugin.yml -i inventory