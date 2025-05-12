General Query
==============

⦾ **What to do if** ``omnia.yml`` **execution fails with a** ``403: Forbidden`` **error when an NFS share is provided as the** ``repo_store_path`` **?**

.. image:: ../../../images/omnia_NFS_403.png

**Potential Cause**: For ``omnia.yml`` execution, the NFS share folder provided in ``repo_store_path`` must have 755 permissions.

**Resolution**: Ensure that the NFS share folder provided as the ``repo_store_path`` has 755 permissions, and re-run ``omnia.yml``.