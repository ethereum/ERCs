#!/bin/bash

BASE_DIR="/path/to/your/repos"

for repo in $(find $BASE_DIR -name ".git" -type d); do
    cd $(dirname $repo)
    echo "Cleaning repo: $(pwd)"
    
    # Remove untracked files
    git clean -f -d
    
    # Fetch and prune branches
    git fetch --prune
    
    # Delete merged local branches
    git branch --merged | grep -v "\*" | xargs -n 1 git branch -d
    
    # Delete remote-tracking branches no longer on remote
    git remote prune origin
    
    echo "Cleaning completed for: $(pwd)"
done
