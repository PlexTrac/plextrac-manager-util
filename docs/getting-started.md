---
# vim: set expandtab ft=markdown ts=4 sw=4 sts=4 tw=100:
title: Getting Started
---

# Getting Started

!!! warning "Minimum Requirements"
    Operating System:
    :   :material-ubuntu: Ubuntu 20.04

    Server Specifications:
    :   RAM: 8192MB or higher

        CPU: 4 cores or higher

        Storage: 128GB or higher

## Installation

The latest release can be retrieved from GitHub:

```console
$ curl -Ls `curl -Ls https://api.github.com/repos/PlexTrac/plextrac-manager-util/releases/latest \
    | jq -r '.assets[].browser_download_url'` \
    > /tmp/plextrac-cli
$ chmod a+x /tmp/plextrac-cli; sudo /tmp/plextrac-cli initialize

______ _         _____              
| ___ \ |       |_   _|             
| |_/ / | _____  _| |_ __ __ _  ___ 
|  __/| |/ _ \ \/ / | '__/ _\ |/ __|
| |   | |  __/>  <| | | | (_| | (__ 
\_|   |_|\___/_/\_\_/_|  \__,_|\___|
                                    

Instance Management Utility v0.1.2


-- Initializing Environment for PlexTrac... -----------------------------------------

...
```

You _must_ switch to the `plextrac` user before continuing.

```console
$ sudo su - plextrac
$ plextrac install
```

## Updates

```console
$ plextrac update
```


## Troubleshooting

!!! tip
    The information below can be used to identify common issues and recommend fixes

```console
$ plextrac check
$ plextrac info
```
