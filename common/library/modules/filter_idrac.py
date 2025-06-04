# Copyright 2025 Dell Inc. or its subsidiaries. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#!/usr/bin/python


"""
return:
idrac_ip_count
failed_idrac
filtered_idrac_count
telemetry_idrac
failed_idrac_count

input:
idrac_ip
idrac_user: "{{ hostvars['localhost']['bmc_username'] }}"
idrac_password: "{{ hostvars['localhost']['bmc_password'] }}"

Global:
datacenter_license: false
firmware_version: false
"""

from ansible.module_utils.basic import AnsibleModule

import requests
from requests.auth import HTTPBasicAuth

class IDRACManager:
    """
    This class manages IDRAC connections.

    :param user: The IDRAC user.
    :param password: The IDRAC password.

    :return: None
    """
    def __init__(self, user, password):
        """
        Initializes an IDRACManager object with a user and password.

        Parameters:
        user (str): The IDRAC user.
        password (str): The IDRAC password.

        Returns:
        None
        """
        self.idrac_user = user
        self.idrac_password = password
        self.idrac_ip_count = 0
        self.failed_idrac = []
        self.failed_idrac_count = 0
        self.telemetry_idrac_count = 0
        self.telemetry_idrac = []

    def get_idrac_inventory(self, ip, redfish_url):
        """
    	Retrieves IDRAC inventory data for a given IP and Redfish URL.

    	Parameters:
    	ip (str): The IP address of the IDRAC.
    	redfish_url (str): The Redfish URL for the IDRAC.

    	Returns:
    	dict: The IDRAC inventory data in JSON format, or None if the request fails.
    	"""
        try:
            response = requests.get(redfish_url,
                                auth=HTTPBasicAuth(self.idrac_user, self.idrac_password),
                                verify=False,
                                timeout=10)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException:
            self.failed_idrac.append(ip)
            self.failed_idrac_count += 1
            return None

    def filter_idrac(self, idrac_ip):
        """
        Filters IDRAC IP addresses based on system information and firmware version.

        Parameters:
            idrac_ip (list): A list of IDRAC IP addresses to filter.

        Returns:
            None
        """
        for ip in idrac_ip:
            try:
                system_info_url = f"https://{ip}/redfish/v1/Systems/System.Embedded.1"
                firmware_info_url = f"https://{ip}/redfish/v1/UpdateService/FirmwareInventory"
                self.idrac_ip_count += 1
                idrac_info = self.get_idrac_inventory(ip, system_info_url)

                if idrac_info is None:
                    raise ValueError

                license_desc = idrac_info.get("LicenseDescription", "")
                primary_status = idrac_info.get("PrimaryStatus", "")

                if not any(keyword in license_desc for keyword in ["iDRAC9", "Data", "License"]):
                    raise ValueError
                if "Healthy" not in primary_status:
                    raise ValueError

                firmware_info = self.get_idrac_inventory(ip, firmware_info_url)
                if firmware_info is None:
                    raise ValueError

                valid_firmware = False
                for index in firmware_info.get("Members", []):
                    fqdd = index.get("FQDD", "")
                    major_version = index.get("MajorVersion", 0)
                    if "iDRAC" in fqdd and int(major_version) > 4:
                        valid_firmware = True
                        break

                if not valid_firmware:
                    raise ValueError

                self.telemetry_idrac.append(ip)
                self.telemetry_idrac_count += 1
            except ValueError:
                self.failed_idrac.append(ip)
                self.failed_idrac_count += 1

def main():
    """Main module function."""
    module_args = dict(
        idrac_ip=dict(type="list", required=True),
        idrac_user=dict(type="str", required=True),
        idrac_password=dict(type="str", required=True)
    )

    module = AnsibleModule(argument_spec=module_args, supports_check_mode=True)
    idrac_ip = module.params["idrac_ip"]
    idrac_user = module.params["idrac_user"]
    idrac_password = module.params["idrac_password"]

    try:
        idrac_manager = IDRACManager(idrac_user, idrac_password)
        idrac_manager.filter_idrac(idrac_ip)
        module.exit_json(changed=False,
                         idrac_ip_count=idrac_manager.idrac_ip_count,
                         telemetry_idrac=idrac_manager.telemetry_idrac,
                         telemetry_idrac_count=idrac_manager.telemetry_idrac_count,
                         failed_idrac=idrac_manager.failed_idrac,
                         failed_idrac_count=idrac_manager.failed_idrac_count)
    except ValueError as e:
        module.fail_json(msg=f"Failed to to get Service Node Group data. {e}")

if __name__ == "__main__":
    main()
