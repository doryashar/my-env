start a new github repo that will contain my essentials for running a new linux instance:
 - private (sub repo, private and encrypted): will be discussed later
 - runme.sh : a script that will get a single password, download the repos (using API KEY), decrypt the private repo and will setup all the env
 - README.md : provides instructions on how to get and run the repo

the runme.sh should setup:
- my desktop links including conky
- all my dotfiles
- all my configuration
- all my passwords
- some of my standalone bins
- it will mount my nfs
- my aliases and scripts
- my docker compose
- my cron jobs (daily backup for example)
etc

running setup should:
- make sure all services are running and healthy (backup, auto-git-update, zerotier, etc)
- make sure all dotfiles are linked (configs, ssh, local, bin).
- mount all network drives
- make sure all packages are installed.
- make sure we are running my zsh with my aliases

shell rc file should make sure path is pointing to my bin files and scripts, and load the base rc file before loading mine

auto git update should monitor the local repo and remote repo. 
- whenever a local update
- whenever a remove update
- whenever a new dotfile is created in the home dir
