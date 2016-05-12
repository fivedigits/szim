#!/usr/bin/env bash

#SZiM is a UNIX citation manager written in BASH.
#    Copyright (C) 2016  Moritz Schönherr
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>

PREFIX="$HOME/.szim"

#
# BEGIN helper functions
#

die () {
	echo "$@" >&2
	exit 1
}

check_sneaky_paths() {
	local path
	for path in "$@"; do
		[[ $path =~ /\.\.$ || $path =~ ^\.\./ || $path =~ /\.\./ || $path =~ ^\.\.$ ]] && die "Error: You've attempted to pass a sneaky path to szim. Go home."
	done
}

check_overwrite() {

	local path="$1"
	
	if [[ -e "$path" ]]; then
		echo "File already exists. Overwrite? [y/N]:"
		read yesno
		
		if [[ "$yesno" == "y" ]]; then
			echo "Overwriting existing file."
		else
			die "User aborted append operation."
		fi
	fi
}

compute_tag() {

	local normalised_path="$1"

	echo "$normalised_path" | tr "/" "_" | tr " " "_" | tr '[:upper:]' '[:lower:]'
}


normalise_szim_path() {

	local path="$1"
	check_sneaky_paths "$1"

	path="${path%/}"
	path="${path#/}"

	echo "$path"
}


#
# BEGIN subcommand functions
#

cmd_annotate() {
	local path=$(normalise_szim_path "$1")
	local full_path="$PREFIX/$path"
	vim "$full_path/remark.txt"
}

cmd_copy_pdf_to_storage() {
	local pdfpath="$1"
	local path="$2"

	check_sneaky_paths "$pdfpath"
	normalise_szim_path "$path"

	local full_path="$PREFIX/$path"
	local filename=$(echo "$path" | tr "/" "_")
	local pdffile="$full_path/$filename.pdf"
	
	mkdir -p "$full_path"

	check_overwrite "$pdffile"

	cp "$pdfpath" "$pdffile"
}

cmd_export_bib() {
	local path="$1"
	check_sneaky_paths "$path"

	check_overwrite "$path"

	echo -n > "$path"	

	for file in $(find "$PREFIX" -name "*.bib")
	do
		echo >> "$path"
		cat "$file" >> "$path"
	done
}

cmd_fetch() {
	local path=$(normalise_szim_path "$1")
	local author="$2"
	local title="$3"
	
	local query_result="$(wget -q "http://www.ams.org/mrlookup?au=$author&ti=$title&format=bibtex" -O - | tr "\n" "|" | grep -oP '@article \{.*?\}\,\|\}')"

	# If multiple matches where found, ask user which one to use
	local title_count=$(echo "$query_result" | grep -oc 'article') 
	if [[ $title_count -gt 1 ]]
	then
		echo "Found multiple matches. Please select one:[1-$title_count]"
		titles=$(echo $query_result | grep -oP 'TITLE = .*?\}\,' | tr "|" "\n")
		while read line
		do
			echo "$line"
		done <<< "$titles"
		read number
		query_result=$(echo "$query_result" | head -n $number | tail -n 1)
	fi
	
	# Now, we are left with one article in query_result. Clean it up
	query_result=$(echo "$query_result" | tr "|" "\n")
	if [[ $(echo "$query_result" | grep '.*[^\s].*') ]]
	then
		echo "Fetched the following entry."
		echo "$query_result"
		# Create tag from path
		local tag=$(compute_tag "$path")

		# Insert into query_result
		query_result=$(echo "$query_result" | sed s/\@article\ *\{\ *[a-zA-Z0-9].*\ *\,/\@article\ \{\ "$tag"\,/)

		# Save result to disk
		mkdir -p "$PREFIX/$path"
		
		local bibfile="$PREFIX/$path/citation.bib"

		check_overwrite "$bibfile"

		echo "$query_result" > "$bibfile"
	else
		echo "Could not retrieve .bib information. Try different author or title."
	fi

	}

cmd_init() {
	mkdir -p -v "$PREFIX"
}

cmd_insert() {
	local path=$(normalise_szim_path "$1")
	local bibpath="$2"
	check_sneaky_paths "$bibpath"
	local full_path="$PREFIX/$path"
	local bibfile="$full_path/citation.bib"
	
	mkdir -p "$full_path"

	check_overwrite "$bibfile"

	cat "$bibpath" > $bibfile
}

cmd_mv_entry() {
	local path1=$(normalise_szim_path "$1")
	local path2=$(normalise_szim_path "$2")
	local source_path="$PREFIX/$path1"
	local target_path="$PREFIX/$path2"

	check_overwrite "$target_path"

	mv $source_path $target_path
}

cmd_rm_entry() {
	local path=$(normalise_szim_path "$1")
	local full_path="$PREFIX/$path"
	
	rm -r $full_path
}

cmd_show() {

    if [[ $# == 1 ]]
    then
        local path=$(normalise_szim_path "$1")
	
	echo
	echo "Details of $path"
	echo

	# If there are annotations, print them
	if [[ -f "$PREFIX/$path/remark.txt" ]]; then
		cat "$PREFIX/$path/remark.txt"
	else
		echo "There are no annotations."
	fi

	pdffiles=$(ls -1 "$PREFIX/$path" | grep '.*.pdf')

	echo
	# If there are pdf files, list them
	if [[ -z "$pdffiles" ]]; then
		echo "There are no .pdf files associated with this entry."
	else
		echo "The following pdf files are associated with this entry:"
		echo "$pdffiles"
	fi

	# If there is a bibfile, cat it

	echo
	if [[ -f "$PREFIX/$path/citation.bib" ]]; then
		echo "The following citation information is associated with this entry."
		cat "$PREFIX/$path/citation.bib"
	else
		echo "There is no .bib file associated with this entry."
	fi
	
    else
	echo "SZiM Store"
	tree --noreport -dC "$PREFIX" | tail -n +2
    fi
	
}

cmd_usage() {
	echo
	cat <<-_EOF
	Usage:
           $PROGRAM annotate citation-name
               Edit the annotation file associated with citation-name, the latter must be a
               sequence of words, delimited by a slash.
           $PROGRAM append pdf-file citation-name
               Copy pdf-file to citation-name, the latter must be a sequence of words, 
               delimited by a slash.
           $PROGRAM fetch citation-name author title
               Fetch bib citation info from mrlookup using author and title for query. Store
               the result in citation-name, which must be a sequence of words, delimited by
               slashes.
           $PROGRAM help
               Show this usage information.
           $PROGRAM init
               Initialize a new szim store.
           $PROGRAM insert citation-name bibfile
               Copy bibfile to the szim store, at location citation-name,
               where citation-name is a sequence of words, delimited by a slash.
           $PROGRAM mv citation-name new-name
               Move citation-name to new-name. Both arguments must be sequences of words,
               delimited by a slash.
           $PROGRAM rm citation-name
               Remove citation-name from szim store. All sub-paths will be removed, too.
               Argument citation-name must be a sequence of words delimited by a slash.
           $PROGRAM show
               Show the structure of the szim store.
	_EOF
}

cmd_view() {

	local path=$(normalise_szim_path "$1")

	# Check wether there is anything to do
	
	pdffiles=$(find "$PREFIX/$path" -name '*.pdf')

	if [[ -z $pdffiles ]]; then
		echo "There are no .pdf files associated with this entry."
	else
		for file in $pdffiles 
		do
			xdg-open $file
		done
	fi

}
#
# END subcommand section
#
	
PROGRAM="${0##*/}"
COMMAND="$1"

case "$COMMAND" in
	annotate) shift;	cmd_annotate "$@" ;;
	append) shift;		cmd_copy_pdf_to_storage "$@" ;;
	export) shift;		cmd_export_bib "$@" ;;
	fetch) shift;		cmd_fetch "$@" ;;
	help) shift;		cmd_usage "$@" ;;
	init) shift;		cmd_init "$@" ;;
	insert|add) shift;	cmd_insert "$@" ;;
	mv) shift;		cmd_mv_entry "$@" ;;
	rm) shift;		cmd_rm_entry "$@" ;;
	show) shift;		cmd_show "$@" ;;
	view) shift;		cmd_view "$@" ;;
	*)			cmd_usage "$@" ;;
esac
exit 0
