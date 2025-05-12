Software package installation
===============================

⦾ **Why does package installation fail or fall back to the Ubuntu OS repository, even when a user repository is specified?**

**Potential Cause**: Ubuntu systems use APT (Advanced Package Tool) to install and manage software. When no priority is set, APT selects and installs the highest available version of a package, regardless of the source repository.

**Resolution**: To ensure the correct package is installed, set a higher priority for the user-repository by creating a preference file. Use the template below to create a ``customrepo.pref`` file. Once created, place it in the ``/etc/apt/preferences.d/`` directory on the OIM node.

**Template**: ::

    Package: <package name>
    Pin: origin <user repo URL>
    Pin-Priority: "650"