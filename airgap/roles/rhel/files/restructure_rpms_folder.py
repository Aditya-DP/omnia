# Copyright 2023 Dell Inc. or its subsidiaries. All Rights Reserved.
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

import sys
import os
import shutil

path= sys.argv[1]

files = [f for f in os.listdir(path)]
for file in files:
    if file.endswith('.rpm'):
        subFolder = os.path.join(path, file[0].lower())
        if not os.path.isdir(subFolder):
            os.makedirs(subFolder)
        if os.path.exists(os.path.join(subFolder, file)):
            os.remove(os.path.join(path, file))
        else:
            shutil.move(os.path.join(path, file), subFolder)
