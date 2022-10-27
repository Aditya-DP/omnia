Storage
=======

The storage role allows users to configure PowerVault Storage devices, BeeGFS and NFS services on the cluster.

First, enter all required parameters in ``omnia/input/storage_config.yml``

+---------------------------------+--------------------------------------------------------------------------------------+-----------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Name                            | Default, accepted values                                                             | Required? | Purpose                                                                                                                                                                                        |
+=================================+======================================================================================+===========+================================================================================================================================================================================================+
| beegfs_support                  | FALSE, TRUE                                                                          | Optional  | This variable is used to install beegfs-client on compute and manager   nodes                                                                                                                  |
+---------------------------------+--------------------------------------------------------------------------------------+-----------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| beegfs_rdma_support             | FALSE, TRUE                                                                          | Optional  | This variable is used if user has RDMA-capable network hardware (e.g.,   InfiniBand)                                                                                                           |
+---------------------------------+--------------------------------------------------------------------------------------+-----------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| beegfs_ofed_kernel_modules_path |                                                                                      | Optional  | The path where separate OFED kernel modules are installed.                                                                                                                                     |
+---------------------------------+--------------------------------------------------------------------------------------+-----------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| beegfs_mgmt_server              |                                                                                      | Required  | BeeGFS management server IP                                                                                                                                                                    |
+---------------------------------+--------------------------------------------------------------------------------------+-----------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| beegfs_mounts                   | "/mnt/beegfs"                                                                        | Optional  | Beegfs-client file system mount location. If ``storage_yml`` is being   used to change the BeeGFS mounts location, set beegfs_unmount_client to TRUE                                           |
+---------------------------------+--------------------------------------------------------------------------------------+-----------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| beegfs_unmount_client           | FALSE, TRUE                                                                          | Optional  | Changing this value to true will unmount running instance of BeeGFS   client and should only be used when decommisioning BeeGFS, changing the mount   location or changing the BeeGFS version. |
+---------------------------------+--------------------------------------------------------------------------------------+-----------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| beegfs_client_version           | 7.2.6                                                                                | Optional  | Beegfs client version needed on compute and manager nodes.                                                                                                                                     |
+---------------------------------+--------------------------------------------------------------------------------------+-----------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| beegfs_version_change           | FALSE, TRUE                                                                          | Optional  | Use this variable to change the BeeGFS version on the target nodes.                                                                                                                            |
+---------------------------------+--------------------------------------------------------------------------------------+-----------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| nfs_client_params               | - { server_ip: , server_share_path: ,   client_share_path: , client_mount_options: } | Optional  | If NFS client services are to be deployed, enter the   configuration required here in JSON format. If left blank, no NFS   configuration takes place. Possible values include:                 |
|                                 |                                                                                      |           |      1. Single NFS file system: A single filesystem from a single NFS server is   mounted.                                                                                                     |
|                                 |                                                                                      |           |      Sample value:                                                                                                                                                                             |
|                                 |                                                                                      |           |      - { server_ip: xx.xx.xx.xx, server_share_path: "/mnt/share",   client_share_path: "/mnt/client", client_mount_options:   "nosuid,rw,sync,hard,intr" }                                     |
|                                 |                                                                                      |           |      2. Multiple Mount NFS file system: Multiple filesystems from a single NFS   server are mounted.                                                                                           |
|                                 |                                                                                      |           |      Sample values:                                                                                                                                                                            |
|                                 |                                                                                      |           |      - { server_ip: xx.xx.xx.xx, server_share_path: "/mnt/server1",   client_share_path: "/mnt/client1", client_mount_options:   "nosuid,rw,sync,hard,intr" }                                  |
|                                 |                                                                                      |           |      - { server_ip: xx.xx.xx.xx, server_share_path: "/mnt/server2",   client_share_path: "/mnt/client2", client_mount_options:   "nosuid,rw,sync,hard,intr" }                                  |
|                                 |                                                                                      |           |      3. Multiple NFS file systems: Multiple filesystems are mounted from   multiple servers. Sample Values:                                                                                    |
|                                 |                                                                                      |           |      - { server_ip: zz.zz.zz.zz, server_share_path: "/mnt/share1",   client_share_path: "/mnt/client1", client_mount_options:   "nosuid,rw,sync,hard,intr"}                                    |
|                                 |                                                                                      |           |      - { server_ip: xx.xx.xx.xx, server_share_path: "/mnt/share2",   client_share_path: "/mnt/client2", client_mount_options:   "nosuid,rw,sync,hard,intr"}                                    |
|                                 |                                                                                      |           |      - { server_ip: yy.yy.yy.yy, server_share_path: "/mnt/share3",   client_share_path: "/mnt/client3", client_mount_options:   "nosuid,rw,sync,hard,intr"}                                    |
+---------------------------------+--------------------------------------------------------------------------------------+-----------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+

.. note:: If ``omnia.yml`` is run with the ``omnia/input/storage_config.yml`` filled out, BeeGFS and NFS client will be set up.

**Installing BeeGFS Client**

* If the user intends to use BeeGFS, ensure that a BeeGFS cluster has been set up with beegfs-mgmtd, beegfs-meta, beegfs-storage services running.

  Ensure that the following ports are open for TCP and UDP connectivity:

        +------+-----------------------------------+
        | Port | Service                           |
        +======+===================================+
        | 8008 | Management service (beegfs-mgmtd) |
        +------+-----------------------------------+
        | 8003 | Storage service (beegfs-storage)  |
        +------+-----------------------------------+
        | 8004 | Client service (beegfs-client)    |
        +------+-----------------------------------+
        | 8005 | Metadata service (beegfs-meta)    |
        +------+-----------------------------------+
        | 8006 | Helper service (beegfs-helperd)   |
        +------+-----------------------------------+



To open the ports required, use the following steps:

    1. ``firewall-cmd --permanent --zone=public --add-port=<port number>/tcp``

    2. ``firewall-cmd --permanent --zone=public --add-port=<port number>/udp``

    3. ``firewall-cmd --reload``

    4. ``systemctl status firewalld``



* Ensure that the nodes in the inventory have been assigned roles: manager, compute, login_node (optional), nfs_node

 .. note:: When working with RHEL, ensure that the BeeGFS configuration is supported using the `link here <../../Overview/SupportMatrix/OperatingSystems/RedHat.html>`_.

**NFS bolt-on**

* Ensure that an external NFS server is running. NFS clients are mounted using the external NFS server's IP.

* Fill out the ``nfs_client_params`` variable in the ``storage_config.yml`` file in JSON format using the samples provided above.

* This role runs on manager, compute and login nodes.

* Make sure that ``/etc/exports`` on the NFS server is populated with the same paths listed as ``server_share_path`` in the ``nfs_client_params`` in ``omnia_config.yml``.

* Post configuration, enable the following services (using this command: ``firewall-cmd --permanent --add-service=<service name>``) and then reload the firewall (using this command: ``firewall-cmd --reload``).

  - nfs

  - rpc-bind

  - mountd

* Omnia supports all NFS mount options. Without user input, the default mount options are nosuid,rw,sync,hard,intr. For a list of mount options, `click here <https://linux.die.net/man/5/nfs>`_.

* The fields listed in ``nfs_client_params`` are:

  - server_ip: IP of NFS server

  - server_share_path: Folder on which NFS server mounted

  - client_share_path: Target directory for the NFS mount on the client. If left empty, respective ``server_share_path value`` will be taken for ``client_share_path``.

  - client_mount_options: The mount options when mounting the NFS export on the client. Default value: nosuid,rw,sync,hard,intr.



* There are 3 ways to configure the feature:

  1. **Single NFS node** : A single NFS filesystem is mounted from a single NFS server. The value of ``nfs_client_params`` would be::

        - { server_ip: xx.xx.xx.xx, server_share_path: "/mnt/share", client_share_path: "/mnt/client", client_mount_options: "nosuid,rw,sync,hard,intr" }

  2. **Multiple Mount NFS Filesystem**: Multiple filesystems are mounted from a single NFS server. The value of ``nfs_client_params`` would be::

    - { server_ip: xx.xx.xx.xx, server_share_path: "/mnt/server1", client_share_path: "/mnt/client1", client_mount_options: "nosuid,rw,sync,hard,intr" }
    - { server_ip: xx.xx.xx.xx, server_share_path: "/mnt/server2", client_share_path: "/mnt/client2", client_mount_options: "nosuid,rw,sync,hard,intr" }

   3. **Multiple NFS Filesystems**: Multiple filesystems are mounted from multiple NFS servers. The value of ``nfs_client_params`` would be::

    - { server_ip: xx.xx.xx.xx, server_share_path: "/mnt/server1", client_share_path: "/mnt/client1", client_mount_options: "nosuid,rw,sync,hard,intr" }
    - { server_ip: yy.yy.yy.yy, server_share_path: "/mnt/server2", client_share_path: "/mnt/client2", client_mount_options: "nosuid,rw,sync,hard,intr" }
    - { server_ip: zz.zz.zz.zz, server_share_path: "/mnt/server3", client_share_path: "/mnt/client3", client_mount_options: "nosuid,rw,sync,hard,intr" }



**To run the playbook:** ::

    cd omnia/storage
    ansible-playbook storage.yml -i inventory

(Where inventory refers to the `host_inventory_file.ini <../../samplefiles.html>`_ listing **only** manager and compute nodes.)
