#!/bin/bash

# Program:	Popular Packages
# Purpose:	Lists popular packages not installed
#
# Author:	Copyright 2011 Xavion
#
# License:
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


# Constants
Author="Xavion"
AppName="Popular Packages"
Version="0.3.0"
Purpose="Lists popular packages not installed"
Details="${AppName} v${Version} by ${Author}"
Filename="`basename "$0"`"
Usage="Usage:
\t${Filename} [options]...\n
Options:
\t-a\t\tDon't fetch AUR descriptions
\t-c\t\tDon't colourise output text
\t-d\t\tDon't fetch any descriptions
\t-m<min>\t\tMinimum popularity percentage
\t-M<max>\t\tMaximum popularity percentage\n
Examples:
\t${Filename} -cd
\t${Filename} -aM60 -m20"
PSURL="https://www.archlinux.de/?page=PackageStatistics"
MinCols=150

# Commands
PackageQuery=`which package-query 2> /dev/null`

# Variables
AUR=1
Colourise=1
ShowDesc=1
Minimum=30
Maximum=100

# Arguments
for Argument; do
	if [[ "${Argument}" =~ -.*a.* ]]; then AUR=0; fi
	if [[ "${Argument}" =~ -.*c.* ]]; then Colourise=0; fi
	if [[ "${Argument}" =~ -.*d.* ]]; then ShowDesc=0; fi
	if [[ "${Argument}" =~ -.*m.* ]]; then Minimum=`echo "${Argument}" | awk -F 'm' '{print $2}'`; fi
	if [[ "${Argument}" =~ -.*M.* ]]; then Maximum=`echo "${Argument}" | awk -F 'M' '{print $2}'`; fi
	if [[ "${Argument}" =~ -.*h.* ]]; then echo -e "${Details}\n${Purpose}"; echo -e "\n${Usage}" >&2; exit; fi
	if [[ "${Argument}" =~ -.*v.* ]]; then echo -e "${Details}" >&2; exit; fi
	if [[ ! "${Argument}" =~ -.* ]]; then echo -e "Error: All arguments must start with a hyphen." >&2; exit; fi
done

# ANSI
if [ ${Colourise} == 1 ]; then
	# Colours
	Reset="\E[0m"
	Bold="\033[1m"
	UnBold="\033[0m"
	Blue="\E[34m"
	Cyan="\E[36m"
	Green="\E[32m"
	Magenta="\E[35m"
	Red="\E[31m"
	Yellow="\E[33m"
fi

# Terminal
if [ `stty size | awk -F ' ' '{print $2}'` -lt ${MinCols} ]; then
	echo -e "${Red}${Bold}Error${UnBold}${Reset}: The terminal width must be at least ${MinCols} columns." >&2
	exit 1
fi

# Maximum
if [ ! `expr ${Maximum} + 1 2> /dev/null` ] || [ ${Maximum} -lt 0 ] || [ ${Maximum} -gt 100 ]; then
	echo -e "${Red}${Bold}Error${UnBold}${Reset}: The maximum popularity must be in the [0-100] range." >&2
	exit 1
fi
# Minimum
if [ ! `expr ${Minimum} + 1 2> /dev/null` ] || [ ${Minimum} -lt 0 ] || [ ${Minimum} -gt 100 ]; then
	echo -e "${Red}${Bold}Error${UnBold}${Reset}: The minimum popularity must be in the [0-100] range." >&2
	exit 1
# Range
elif [ ${Maximum} -lt ${Minimum} ]; then
	echo -e "${Red}${Bold}Error${UnBold}${Reset}: The maximum popularity must be greater than the minimum (${Minimum})." >&2
	exit 1
fi

# Retrieve
echo -e "${Green}Information${Reset}: Retrieving the package statistics ...\n"
Stats="`wget -qO- ${PSURL} | grep -e '<tr><td style="width: 200px;">' -e '&nbsp;%'`"

# Retrieved
if [ "${Stats}" ]; then
	echo -e "${Green}Information${Reset}: Packages with ${Blue}${Bold}${Minimum}${UnBold}${Reset}-${Blue}${Bold}${Maximum}${UnBold}${Reset}% popularity are permitted."

	# Inits
	LineNumIn=0
	LineNumOut=0
	NumLines=`echo "${Stats}" | wc -l`
	Repository=""
	RepoActive=0
	LastValid=0
	Packages="`${PackageQuery} -Q -f %n 2> /dev/null`"

	echo "${Stats}" | while read StatLine; do

		# Progress
		let LineNumIn=${LineNumIn}+1

		# Repository
		if [ "`echo ${StatLine} | grep '<tr><th>'`" ]; then
			LastValid=1
			Repository=`echo ${StatLine} | awk -F '<tr><th>' '{print $2}' | awk -F '</th><td>' '{print $1}'`

			echo -e "\n\n${Green}Information${Reset}: Listing ${Magenta}${Bold}${Repository}${UnBold}${Reset} repository packages ...\n"

			# Active
			RepoActive=0
			if [ "`${PackageQuery} -Sl -f %n ${Repository} 2> /dev/null`" ]; then
				RepoActive=1
			# Sync
			elif [ ${ShowDesc} == 1 ] && [ "${Repository}" != "unknown" ]; then
				echo -e "${Magenta}Warning${Reset}: This repository isn't synched; no descriptions are available.\n"
			fi

			printf "%4s%s%-12s%-14s%-34s%-s%s\n" "" "`echo -e ${Bold}`" "Progress" "Popularity" "Package" "Description" "`echo -e ${Reset}`"
			printf "%4s%s\n" "" "-------------------------------------------------------------------------------------------------------------------------------------------------"
		fi

		# Entry
		if [ ${LastValid} == 1 ]; then
			# Package
			if [ "`echo ${StatLine} | grep '<tr><td style="width: 200px;">'`" ]; then
				Package=`echo ${StatLine} | awk -F '<tr><td style="width: 200px;">' '{print $2}' | awk -F '</td><td><table style="width:100%;">' '{print $1}'`
			# Popularity
			elif [ "`echo ${StatLine} | grep '&nbsp;%'`" ]; then
				Popularity=`echo ${StatLine} | awk -F '.' '{print $1}'`
				PacLine=`echo "${Packages}" | grep "${Package}"`

				# Valid
				if [ ${Popularity} -ge ${Minimum} ] && [ ${Popularity} -le ${Maximum} ]; then
					# Absent
					if [ ! "${PacLine}" ]; then
						# Progress
						let Progress=100*${LineNumIn}/${NumLines}
						let LineNumOut=${LineNumOut}+1
						let OddLine=${LineNumOut}%2

						# Description
						Description=""
						if [ ${ShowDesc} == 1 ]; then
							# Sync
							if [ ${RepoActive} == 1 ]; then
								Description=`${PackageQuery} -S -f %d ${Package} 2> /dev/null`
							# AUR
							elif [ "${Repository}" == "unknown" ] && [ ${AUR} == 1 ]; then
								Description=`${PackageQuery} -A -f %d ${Package} 2> /dev/null`
							fi
						fi

						# Colour
						if [ ${OddLine} == 1 ]; then
							Colour=${Cyan}
						else
							Colour=${Yellow}
						fi

						printf "%9s%s%13s%8s%s%-34s%s%-s%s\n" "${Progress}%" "`echo -e ${Colour}`" "${Popularity}%" "" "`echo -e ${Bold}`" "${Package}" "`echo -e ${UnBold}${Colour}`" "${Description}" "`echo -e ${Reset}`"
					fi
				# Below
				elif [ ${Popularity} -lt ${Minimum} ]; then
					LastValid=0
				fi
			fi
		fi
	done
# Error
else
	echo -e "${Red}${Bold}Error${UnBold}${Reset}: The package statistics couldn't be retrieved; check your network settings and try again." >&2
	exit 1
fi
