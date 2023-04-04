#!/bin/bash
# This script removes Quartus temporary files from the fpga_src directory.

# Find SRCDIR from the pathname of this script
SRCDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/.. && pwd )"

# Change to fpga_src/qbuild/ directory and remove files listed in .gitignore
cd ${SRCDIR}/fpga_src/qbuild/
rm -r `cat .gitignore | egrep -v '^#'`
