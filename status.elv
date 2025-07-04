# Copyright (c) 2019-2020, Cody Opel <cwopel@chlorm.net>
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


use str
use github.com/chlorm/elvish-stl/exec
use github.com/chlorm/elvish-stl/list
use github.com/chlorm/elvish-stl/map
use github.com/chlorm/elvish-stl/re


fn -parse-xy {|line|
    var xyr = [
        &staged=$line[0..1]
        &unstaged=$line[1..2]
    ]

    var xy = [
        &staged=[&]
        &unstaged=[&]
    ]

    # NOTE: X is purposely omitted to throw an error.
    for i [ 'staged' 'unstaged' ] {
        var char = $xyr[$i]
        if (==s $char '.') {
            set xy[$i]['unmodifed'] = $true
        } elif (==s $char 'A') {
            set xy[$i]['added'] = $true
        } elif (==s $char 'C') {
            set xy[$i]['copied'] = $true
        } elif (==s $char 'D') {
            set xy[$i]['deleted'] = $true
        } elif (==s $char 'M') {
            set xy[$i]['modified'] = $true
        } elif (==s $char 'R') {
            set xy[$i]['renamed'] = $true
        } elif (==s $char 'T') {
            set xy[$i]['typechange'] = $true
        } elif (==s $char 'U') {
            set xy[$i]['unmerged'] = $true
        } else {
            put $i' '$xyr[$i] >&2
            fail 'not a valid XY char'
        }
    }

    put $xy
}

fn -parse-sub {|line|
    var s = [
        &commit=$line[1..2]
        &tracked=$line[2..3]
        &untracked=$line[3..4]
    ]

    var submodule = [&]

    if (==s $line[0..1] 'S') {
        for i [ (map:keys $s) ] {
            if (list:has [ 'C' 'M' 'U' ] $s[$i]) {
                set submodule[$i] = $true
            } else {
                if (!=s '.' $s[$i]) {
                put $s[$i] >&2
                fail 'invalid submodule char'
                }
            }
        }
    }

    put $submodule
}

fn -map-modified {|s|
    put [
        &type=$s[0]
        &xy=$s[1]
        &sub=$s[2]
        &mode=[
            &head=$s[3]
            &index=$s[4]
            &worktree=$s[5]
        ]
        &obj=[
            &head=$s[6]
            &index=$s[7]
        ]
        &path=(str:join " " $s[8..])
    ]
}

fn -parse-modified {|status input|
    var path = $input[path]

    var xy = (-parse-xy $input['xy'])
    set status['paths'][$path]['staged'] = $xy['staged']
    set status['paths'][$path]['unstaged'] = $xy['unstaged']
    var sub = (-parse-sub $input['sub'])
    if (> (count $sub) 0) {
        set status['paths'][$path]['submodule'] = $sub
    }
    set status['paths'][$path]['mode'] = $input['mode']
    set status['paths'][$path]['object'] = $input['obj']

    put $status
}

fn -map-renamed-copied {|s|
    var p = [ (re:splits '\t' (str:join " " $s[9..])) ]
    put [
        &type=$s[0]
        &xy=$s[1]
        &sub=$s[2]
        &mode=[
            &head=$s[3]
            &index=$s[4]
            &worktree=$s[5]
        ]
        &obj=[
            &head=$s[6]
            &index=$s[7]
        ]
        &score=$s[8]
        &path=$p[0]
        &origpath=$p[1]
    ]
}

fn -parse-rename-copied {|status input|
    var path = $input['path']

    var xy = (-parse-xy $input['xy'])
    set status['paths'][$path]['staged'] = $xy['staged']
    set status['paths'][$path]['unstaged'] = $xy['unstaged']
    var sub = (-parse-sub $input['sub'])
    if (> (count $sub) 0) {
        set status['paths'][$path]['submodule'] = $sub
    }
    set status['paths'][$path]['mode'] = $input['mode']
    set status['paths'][$path]['object'] = $input['obj']
    set status['paths'][$path]['score'] = $input['score']
    set status['paths'][$path]['origpath'] = $input['origpath']

    put $status
}

fn -map-unmerged {|s|
    put [
        &type=$s[0]
        &xy=$s[1]
        &sub=$s[2]
        &mode=[
            &stage1=$s[3]
            &stage2=$s[4]
            &stage3=$s[5]
            &worktree=$s[6]
        ]
        &obj=[
            &stage1=$s[7]
            &stage2=$s[8]
            &stage3=$s[9]
        ]
        &path=(str:join " " $s[10..])
    ]
}

fn -parse-unmerged {|status input|
    var path = $input['path']

    var xy = (-parse-xy $input['xy'])
    set status['paths'][$path]['staged'] = $xy['staged']
    set status['paths'][$path]['unstaged'] = $xy['unstaged']
    var sub = (-parse-sub $input['sub'])
    if (> (count $sub) 0) {
        set status['paths'][$path]['submodule'] = $sub
    }
    set status['paths'][$path]['mode'] = $input['mode']
    set status['paths'][$path]['object'] = $input['obj']

    put $status
}

# Initializes a path object if it doesn't exist
fn -initialize-path {|status path|
    try {
        var _ = $status['paths'][$path]
    } catch _ {
        set status['paths'][$path] = [&]
    }

    put $status
}

# Returns the result of `git status` as a structured object.
# XXX: object structure and naming is not finalized and subject to change
fn status {
    var gitStatusOutput = [ ]
    try {
        set gitStatusOutput = [(
            exec:cmd-out 'git' 'status' '--porcelain=2' '--branch' '--ignored'
        )]
    } catch e {
        fail $e
    }

    var gitStatus = [
        &branch=[&]
        &paths=[&]
    ]

    for i $gitStatusOutput {
        var line = [ (str:split " " $i) ]
        var char = $line[0]
        if (==s $char '#') {
            var header = (re:find 'branch.([a-z]+)' $line[1])
            if (==s $header 'ab') {
                set gitStatus[branch][ahead] = (re:find '\+(\d+)' $line[2])
                set gitStatus[branch][behind] = (re:find '-(\d+)' $line[3])
            } else {
                set gitStatus[branch][$header] = $line[2]
            }
        } elif (==s $char '1') {
            var input = (-map-modified $line)
            set gitStatus = (-initialize-path $gitStatus $input['path'])
            set gitStatus = (-parse-modified $gitStatus $input)
        } elif (==s $char '2') {
            var input = (-map-modified $line)
            set gitStatus = (-initialize-path $gitStatus $input['path'])
            set gitStatus = (-parse-renamed-copied $gitStatus $input)
        } elif (==s $char 'u') {
            var input = (-map-modified $line)
            set gitStatus = (-initialize-path $gitStatus $input['path'])
            set gitStatus = (-parse-unmerged $gitStatus $input)
        } elif (==s $char '?') {
            var path = (str:join " " $line[1..])
            set gitStatus = (-initialize-path $gitStatus $path)
            set gitStatus['paths'][$path]['untracked'] = $true
        } elif (==s $char '!') {
            var path = (str:join " " $line[1..])
            set gitStatus = (-initialize-path $gitStatus $path)
            set gitStatus['paths'][$path]['ignored'] = $true
        } else {
            put $char >&2
            fail 'invalid type'
        }
    }

    put $gitStatus
}

fn -count-generic {|status key|
    var count = 0
    for i [ (map:keys $status['paths']) ] {
        try {
            if $status['paths'][$i][$key] {
                set count = (+ $count 1)
            }
        } catch _ { }
    }

    put $count
}

fn count-unstaged {|status|
    -count-generic $status 'unstaged'
}

fn count-untracked {|status|
    -count-generic $status 'untracked'
}

fn count-deleted {|status|
    -count-generic $status 'undeleted'
}

