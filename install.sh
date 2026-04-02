 #!/bin/bash

 # Needed to default to zsh shell when SSH'ing in
 sudo chsh "$(id -un)" --shell "/usr/bin/zsh"

 # Install fd and ripgrep
 sudo apt-get update -qq
 sudo apt-get install -y fd-find ripgrep
 curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
 rtk init --global

   # fd installs as fdfind on Debian/Ubuntu, symlink to fd
   sudo ln -sf "$(which fdfind)" /usr/local/bin/fd

   create_symlinks() {
       # Get the directory in which this script lives.
       script_dir=$(dirname "$(readlink -f "$0")")

       # Get a list of all files in this directory that start with a dot.
       files=$(find -maxdepth 1 -type f -name ".*")

       # Create a symbolic link to each file in the home directory.
       for file in $files; do
           name=$(basename $file)
           echo "Creating symlink to $name in home directory."
           rm -rf ~/$name
           ln -s $script_dir/$name ~/$name
       done
   }

   create_symlinks
