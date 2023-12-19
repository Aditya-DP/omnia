#!/bin/bash

[ -d /opt/omnia ] || mkdir /opt/omnia
[ -d /var/log/omnia ] || mkdir /var/log/omnia

default_py_version="3.9"
validate_rocky_os="$(cat /etc/os-release | grep 'ID="rocky"' | wc -l)"
validate_ubuntu_os="$(cat /etc/os-release | grep 'ID=ubuntu' | wc -l)"

sys_py_version="$(python3 --version)"
echo "System Python version: $sys_py_version"

if [[ "$validate_rocky_os" == "1" ]];
then
 echo "------------------------"
 echo "INSTALLING EPEL RELEASE:"
 echo "------------------------"
 dnf install epel-release -y
fi

if [[ "$validate_ubuntu_os" == "1" ]];
then
    apt-add-repository ppa:deadsnakes/ppa -y
    echo "----------------------"
    echo "INSTALLING PYTHON 3.9:"
    echo "----------------------"
    apt install python3.9* python3-pip -y
    echo "--------------"
    echo "UPGRADING PIP:"
    echo "--------------"
    python3.9 -m pip install --upgrade pip
else
    if [[ $(echo $sys_py_version | grep "3.9" | wc -l) != "1" || $(echo $sys_py_version | grep "Python" | wc -l) != "1" ]];
    then
    echo "----------------------"
    echo "INSTALLING PYTHON 3.9:"
    echo "----------------------"
    dnf install python39 -y
    fi
    echo "--------------"
    echo "UPGRADING PIP:"
    echo "--------------"
    python3.9 -m pip install --upgrade pip
fi
echo "-------------------"
echo "INSTALLING ANSIBLE:"
echo "-------------------"

installed_ansible_version=$( ansible --version 2>/dev/null | grep -oP 'ansible \[core \K\d+\.\d+\.\d+' | sed 's/]//')
target_ansible_version="2.14.13"

if [[ ! -z "$installed_ansible_version" && "$(echo -e "$installed_ansible_version\n$target_ansible_version" | sort -V | tail -n1)" != "$target_ansible_version" ]];
then
    echo "Error: Higher version of Ansible ($installed_ansible_version) is already installed. Please uninstall the existing ansible and re-run the prereq.sh again to install $target_ansible_version"
    exit 1
fi

if [[ ! -z "$installed_ansible_version" && "$(echo -e "$installed_ansible_version\n$target_ansible_version" | sort -V | head -n1)" != "$target_ansible_version" ]];
then
    echo "Warning: prereq.sh is uninstalling the existing Ansible ($installed_ansible_version) and installing the $target_ansible_version"
fi

python3.9 -m pip install ansible==7.7.0 cryptography==41.0.7
python3.9 -m pip install jinja2==3.1.2

if [[ "$validate_ubuntu_os" == "1" ]];
then
    apt install git -y
else
    dnf install git-lfs -y
    git lfs pull

    selinux_count="$(grep "^SELINUX=disabled" /etc/selinux/config | wc -l)"
    if [[ $selinux_count == 0 ]];
    then
    echo "------------------"
    echo "DISABLING SELINUX:"
    echo "------------------"
    sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
    echo "SELinux is disabled. Reboot system to notice the change in status before executing playbooks in control plane!!"
    fi
fi
echo ""
echo ""
echo ""
echo "Download the ISO file required to provision in the control plane."
echo ""
echo "Download OFED ISO and CUDA RPM file to install OFED and CUDA during provisioning."
echo ""
echo "Please configure all the NICs and set the hostname for the control plane in the format hostname.domain_name. Eg: controlplane.omnia.test"
echo ""
echo "Once IP and hostname is set, provide inputs in input/provision_config.yml and execute the playbook provision/provision.yml"
echo ""
echo "For more information: https://omnia-doc.readthedocs.io/en/latest/InstallationGuides/InstallingProvisionTool/index.html"
