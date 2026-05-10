#!/bin/bash

git add -A

git status

echo "Nhap commit message:"
read msg

git commit -m "$msg"
git push
