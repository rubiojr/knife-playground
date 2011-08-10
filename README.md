# knife-playground

Playground for various Opscode Chef Knife plugins

# Installing

    gem install knife-playground

# Commands Available

**knife pg config settings**

Print Chef::Config settings

    knife pg config settings

**knife pg clientnode delete CLIENT**

Delete client + node from Opscode Chef Server
    
    knife pg clientnode delete bluepill

**knife pg gitcook upload Git-URL1 GitURL2 ...**

Upload a cookbook to a Chef Server downloading it first from a Git repository

    knife pg git cookbook upload git://github.com/rubiojr/yum-stress-cookbook.git

# Copyright

Copyright (c) 2011 Sergio Rubio. See LICENSE.txt for
further details.

