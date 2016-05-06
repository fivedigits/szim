#!/usr/bin/env bash

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

#
# BEGIN subcommand functions
#

cmd_annotate() {
	check_sneaky_paths "$1"
	local full_path="$PREFIX/$1"
	vim "$full_path/remark.txt"
}

cmd_copy_pdf_to_storage() {
	local path="$2"
	check_sneaky_paths "$path"
	local full_path="$PREFIX/$path"
	local filename=$(echo "$path" | tr "/" "_")
	local pdffile="$full_path/$filename.pdf"
	
	mkdir -p "$full_path"
	cp "$1" "$pdffile"
}

cmd_fetch() {
	local path="$1"
	check_sneaky_paths "$path"
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
		local tag=$(echo "$path" | tr "/" "_" | tr " " "_" | tr '[:upper:]' '[:lower:]')

		# Insert into query_result
		query_result=$(echo "$query_result" | sed s/\@article\ *\{\ *[a-zA-Z0-9].*\ *\,/\@article\ \{\ "$tag"\,/)

		# Save result to disk, probably should check whether override or not
		mkdir -p "$PREFIX/$path"
		echo "$query_result" > "$PREFIX/$path/citation.bib"
	else
		echo "Could not retrieve .bib information. Try different author or title."
	fi

	}

cmd_init() {
	mkdir -p -v "$PREFIX"
}

cmd_insert() {
	local path="$1"
	local bibpath="$2"
	check_sneaky_paths "$path"
	check_sneaky_paths "$bibpath"
	local full_path="$PREFIX/$path"
	local bibfile="$full_path/citation.bib"
	
	mkdir -p "$full_path"
	cat "$bibpath" > $bibfile
}

cmd_mv_entry() {
	check_sneaky_paths "$1"
	check_sneaky_paths "$2"
	local source_path="$PREFIX/$1"
	local target_path="$PREFIX/$2"

	mv $source_path $target_path
}

cmd_rm_entry() {
	local path="$1"
	check_sneaky_paths "$path"
	local full_path="$PREFIX/$path"
	
	rm -r $full_path
}

cmd_show() {
	echo "SZiM Store"
	tree --noreport -dC "$PREFIX" | tail -n +2
}

cmd_usage() {
	echo "USAGE: szim"
}

#
# END subcommand section
#
	
PROGRAM="${0##*/}"
COMMAND="$1"

case "$COMMAND" in
	annotate) shift;	cmd_annotate "$@" ;;
	append) shift;		cmd_copy_pdf_to_storage "$@" ;;
	fetch) shift;		cmd_fetch "$@" ;;
	help) shift;		cmd_usage "$@" ;;
	init) shift;		cmd_init "$@" ;;
	insert|add) shift;	cmd_insert "$@" ;;
	move|mv) shift;		cmd_mv_entry "$@" ;;
	remove|rm) shift;	cmd_rm_entry "$@" ;;
	show) shift;		cmd_show "$@" ;;
	*)			cmd_show "$@" ;;
esac
exit 0
