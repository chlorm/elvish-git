# Copyright (c) 2022, Cody Opel <cwopel@chlorm.net>
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


use file file_
use path path_
use github.com/chlorm/elvish-stl/os


fn -deleted-files {
    e:git log --all --pretty=format: --name-only --diff-filter=D | peach {|p|
        if (==s $p '') {
            continue
        }
        put $p
    }
}

fn prune-paths {|@paths|
    var args = [ ]
    for p $paths {
        if (os:exists $p) {
            continue
        }
        echo 'pruning: '$p >&2
        set args = [ $@args '--path' $p ]
    }
    if (< (count $args) 1) {
        fail
    }
    e:git filter-repo $@args --invert-paths --force
}

fn prune-deleted {
    while $true {
        var f = [ ]
        -deleted-files | each {|x|
            set f = [ $@f $x ]
        }

        prune-paths $@f
        # Recurse until no references are found
        try {
            prune-deleted
        } catch _ {
            break
        }
    }
}

fn move-path {|sourcePath targetPath|
    echo 'moving: '$sourcePath' -> '$targetPath >&2
    e:git filter-repo '--path-rename' $sourcePath':'$targetPath
}

fn commit-message-replace {|matchStr newStr|
    var expressions = (path_:temp-file)
    print '
regex:'$matchStr'==>'$newStr'
' > $expressions['name']

    try {
        e:git filter-repo --replace-message $expressions['name']
    } catch e {
        fail $e
    } finally {
        file_:close $expressions
    }
}
