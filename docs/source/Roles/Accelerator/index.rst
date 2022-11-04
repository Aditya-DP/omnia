Accelerator
============

The accelerator role allows users to  set up the `AMD ROCm <https://www.amd.com/en/graphics/servers-solutions-rocm>`_ platform or the `CUDA Nvidia toolkit <https://developer.nvidia.com/cuda-zone>`_. These tools allow users to unlock the potential of installed GPUs.

Enter all required parameters in ``omnia/input/accelerator_config.yml``.

+----------------------+--------------------------+-----------+----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Name                 | Default, Accepted Values | Required? | Information                                                                                                                                                                                                          |
+======================+==========================+===========+======================================================================================================================================================================================================================+
| amd_gpu_version      | latest                   | optional  | Required AMD GPU driver version                                                                                                                                                                                      |
+----------------------+--------------------------+-----------+----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| amd_rocm_version     | latest                   | optional  | Required AMD ROCm driver version                                                                                                                                                                                     |
+----------------------+--------------------------+-----------+----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| cuda_toolkit_version | latest                   | optional  | Required CUDA toolkit version                                                                                                                                                                                        |
+----------------------+--------------------------+-----------+----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| cuda_toolkit_path    |                          | optional  | If the latest cuda toolkit is not required, provide an offline copy of   the toolkit installer in the path specified. (Take an RPM copy of the toolkit   from `here <https://developer.nvidia.com/cuda-downloads>`_) |
+----------------------+--------------------------+-----------+----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| cuda_stream          | latest-dkms              | optional  | A stream in CUDA is a sequence of operations that execute on the device   in the order in which they are issued by the host code.                                                                                    |
+----------------------+--------------------------+-----------+----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+

.. note::

    * For target nodes running RedHat, ensure that redhat subscription is enabled before running ``accelerator.yml``

    * The post-provision script calls ``network.yml`` to install OFED drivers.

To install all the latest GPU drivers and toolkits, run: ::

    ansible-playbook accelerator.yml -i inventory

(where inventory consists of manager, compute and login nodes)

The following configurations take place when running ``accelerator.yml``
    i. Servers with AMD GPUs are identified and the latest GPU drivers and ROCm platforms are downloaded and installed.
    ii. Servers with NVIDIA GPUs are identified and the specified CUDA toolkit is downloaded and installed.
    iii. For the rare servers with both NVIDIA and AMD GPUs installed, all the above mentioned download-ables are installed to the server.
    iv. Servers with neither GPU are skipped.
