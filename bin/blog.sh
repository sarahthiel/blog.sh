#!/usr/bin/env bash

# This file is licensed under the MIT license.
# See the AUTHORS and LICENSE files for more information.
#
# repository:       https://github.com/sebastianthiel/blog.sh
# bug tracking:     https://github.com/sebastianthiel/blog.sh/issues

########################################
# GLOBALS                              #
########################################
SCRIPTNAME="${0##*/}"
SCRIPT_DIR="$(dirname $(readlink -f "$0"))"
PROJECT_DIR=""
WORK_DIR=""

# sets default configuration values
# values can be overridden in sites.conf
set_default_config(){
	ASSET_DIR="assets"
	TEMPLATE_DIR="template"
	POST_DIR="posts"
	POST_URL="${POST_DIR}"

	DATE_LOCALE="C"
	DATE_FORMAT="%d. %B %Y"
	DATE_FORMAT_ISO="%Y-%m-%d %H:%M:%S"
	DATE_FORMAT_RFC="%a, %d %b %Y %H:%M:%S %z"

	SITE_TITLE=""
	SITE_SUBTITLE=""
	SITE_URL=""
	SITE_LANGUAGE="en"
}

# sets global for project directory
# $1
set_project_dir(){
	if [ ! -d "${1}" ]; then
		die "directory \"${1}\" not found"
	fi
	PROJECT_DIR="$(realpath ${1})"
}

# creates work directory
create_work_dir(){
	WORK_DIR="$(mktemp -d)"
}

########################################
# HELPER FUNCTIONS                     #
########################################
# output error and exit
die() {
	echo "$@" >&2
	exit 1
}

# reads configuration file from project
read_project_config(){
	local config_file="${PROJECT_DIR}/site.conf"
	set_default_config

	if [ -f "${config_file}" ]; then
		source "${config_file}" &> /dev/null
	fi
}

tmp_file(){
	echo "$(mktemp -p "${WORK_DIR}")"
}

# convert markdown to html
#
# $1 markdown file
# $2 target file
md2html(){
	$SCRIPT_DIR/markdown.sh "$1" > $2
}

# $1 date
# $2 date_format
format_date(){
	LC_ALL=${DATE_LOCALE} date -d "$1" "+$2"
}


# split markdown file into
# * .metadata
# * .excerpt
# * .content
#
# $1	markdown file
slice_markdown(){
	local temp_filename="${WORK_DIR}/tmp/${1##*/}"
	local part=""
	# create empty files
	echo -n "" > "${temp_filename}.meta"
	echo -n "" > "${temp_filename}.excerpt"
	echo -n "" > "${temp_filename}.content"

	while IFS= read -r line; do
	if [[ "$line" == "---" ]]; then
		if [[ $part == "" ]]; then
			part="meta"
		elif [[ $part == "meta" ]]; then
			part="excerpt"
		elif [[ $part == "excerpt" ]]; then
			part="content"
		else
			echo "$line" >> "${temp_filename}.content"
		fi
	elif [[ $part == "meta" ]]; then
		echo "$line" >> "${temp_filename}.meta"
	elif [[ $part == "excerpt" ]]; then
		echo "$line" >> "${temp_filename}.excerpt"
		echo "$line" >> "${temp_filename}.content"
	elif [[ $part == "content" ]]; then
		echo "$line" >> "${temp_filename}.content"
	fi
	done < "$1"
	echo ${temp_filename}
}

# reads metadata
#
# $1 metadata file
# $2 variable name
read_metadata(){
	[[ -z $1 ]] && exit

	while IFS= read -r line; do
		local key=$(cut -d ":" -f1 <<< "${line}")
		if [[ "$key" == "$2" ]]; then
			echo $(cut -d ":" -s -f2- <<< "${line}" | sed 's/^[ \t]*//;s/[ \t]*$//')
			exit
		fi
	done < "$1"
}

########################################
# TEMPLATE FUNCTIONS                   #
########################################
# $1	metadata file
# $2	page_type
build_html_head(){
	local target_file="$(tmp_file)"
	local title="${SITE_TITLE}";

	local page_title=""
	
	[[ -n "$1" ]] && page_title=$(read_metadata "$1" "title")
	[[ -n "$page_title" ]] && title="${title} | ${page_title}"

	sed -e "s/%TITLE%/${title}/g" "${PROJECT_DIR}/${TEMPLATE_DIR}/html-head.html" | \
	sed -e "s/%LANGUAGE_CODE%/${SITE_LANGUAGE}/g" | \
	sed -e "s/%PAGETYPE%/$2/g" | \
	sed -e "s~%SITEROOT%~${SITE_URL}~g" | \
	sed -e "s/%SITENAME%/${SITE_TITLE}/g" | \
	sed -e "s/%SUBTITLE%/${SITE_SUBTITLE}/g" \
	> "${target_file}"	
	echo $target_file
}

# $1	metadata file
# $2	url
build_excerpt_head(){
	local target_file="$(tmp_file)"
	local title=$(read_metadata "$1" "title")
	local date=$(read_metadata "$1" "data")
	local post_date=$(format_date "${date}" "${DATE_FORMAT}")
	local iso_date=$(format_date "${date}" "${DATE_FORMAT_ISO}")

	sed -e "s/%ISODATE%/${iso_date}/g" "${PROJECT_DIR}/${TEMPLATE_DIR}/excerpt-head.html" | \
	sed -e "s/%DATE%/${post_date}/g" | \
	sed -e "s~%URL%~$2~g" | \
	sed -e "s/%TITLE%/${title}/g" > "${target_file}"
	echo $target_file
}

# $1	metadata file
# $2	url
build_excerpt_foot(){
	local target_file="$(tmp_file)"
	local title=$(read_metadata "$1" "title")
	local date=$(read_metadata "$1" "data")
	local post_date=$(format_date "${date}" "${DATE_FORMAT}")
	local iso_date=$(format_date "${date}" "${DATE_FORMAT_ISO}")

	sed -e "s~%URL%~$2~g" "${PROJECT_DIR}/${TEMPLATE_DIR}/excerpt-foot.html" > "${target_file}"
	echo $target_file
}

# $1	metadata file
build_post_head(){
	local target_file="$(tmp_file)"
	local title=$(read_metadata "$1" "title")
	local date=$(read_metadata "$1" "data")
	local post_date=$(format_date "${date}" "${DATE_FORMAT}")
	local iso_date=$(format_date "${date}" "${DATE_FORMAT_ISO}")

	sed -e "s/%ISODATE%/${iso_date}/g" "${PROJECT_DIR}/${TEMPLATE_DIR}/post-head.html" | \
	sed -e "s/%DATE%/${post_date}/g" | \
	sed -e "s/%TITLE%/${title}/g" \
	> "${target_file}"
	echo $target_file
}

# $1	metadata file
build_post_foot(){
	local target_file="$(tmp_file)"
	cp "${PROJECT_DIR}/${TEMPLATE_DIR}/post-foot.html" "${target_file}"
	echo $target_file
}

# $1	metadata file
build_archive_head(){
	local target_file="$(tmp_file)"
	cp "${PROJECT_DIR}/${TEMPLATE_DIR}/archive-head.html" "${target_file}"
	echo $target_file
}

# $1	metadata file
# $2	url
build_archive_row(){
	local target_file="$(tmp_file)"
	local title=$(read_metadata "$1" "title")
	local date=$(read_metadata "$1" "date")
	local post_date=$(format_date "${date}" "${DATE_FORMAT}")
	local iso_date=$(format_date "${date}" "${DATE_FORMAT_ISO}")

	sed -e "s~%URL%~$2~g" "${PROJECT_DIR}/${TEMPLATE_DIR}/archive-row.html" | \
	sed -e "s/%ISODATE%/${iso_date}/g" | \
	sed -e "s/%DATE%/${post_date}/g" | \
	sed -e "s/%TITLE%/${title}/g" > "${target_file}"
	echo $target_file
}

# $1	metadata file
build_archive_foot(){
	local target_file="$(tmp_file)"
	cp "${PROJECT_DIR}/${TEMPLATE_DIR}/archive-foot.html" "${target_file}"
	echo $target_file
}

# $1	metadata file
build_html_foot(){
	local target_file="$(tmp_file)"
	cp "${PROJECT_DIR}/${TEMPLATE_DIR}/html-foot.html" "${target_file}"
	echo $target_file
}

# $1	metadata file
build_feed_head(){
	local target_file="$(tmp_file)"
	local title="${SITE_TITLE}";
	local date=$(format_date "now" "${DATE_FORMAT_RFC}")

	sed -e "s/%SITENAME%/${SITE_TITLE}/g"  "${PROJECT_DIR}/${TEMPLATE_DIR}/feed-head.rss"| \
	sed -e "s~%SITEROOT%~${SITE_URL}~g" | \
	sed -e "s/%SUBTITLE%/${SITE_SUBTITLE}/g" | \
	sed -e "s/%LANGUAGE%/${SITE_LANGUAGE}/g" | \
	sed -e "s/%DATE%/${date}/g" > "${target_file}"	
	echo $target_file
}

# $1	metadata file
# $2	url
build_feed_item_head(){
	local target_file="$(tmp_file)"
	local title=$(read_metadata "$1" "title")
	local date=$(read_metadata "$1" "date")
	local iso_date=$(format_date "${date}" "${DATE_FORMAT_RFC}")
	local url="${SITE_URL}/${2}"

	sed -e "s~%URL%~${url}~g" "${PROJECT_DIR}/${TEMPLATE_DIR}/feed-item-head.rss" | \
	sed -e "s/%TITLE%/${title}/g" | \
	sed -e "s/%DATE%/${iso_date}/g" > "${target_file}"
	echo $target_file
}


# $1	metadata file
build_feed_item_foot(){
	local target_file="$(tmp_file)"
	cp "${PROJECT_DIR}/${TEMPLATE_DIR}/feed-item-foot.rss" "${target_file}"
	echo $target_file
}

# $1	metadata file
build_feed_foot(){
	local target_file="$(tmp_file)"
	cp "${PROJECT_DIR}/${TEMPLATE_DIR}/feed-foot.rss" "${target_file}"
	echo $target_file
}
########################################
# CMD BUILD FUNCTIONS                  #
########################################

copy_assets(){
	cp -a "${PROJECT_DIR}/${ASSET_DIR}/." "${WORK_DIR}/public/${ASSET_DIR}"
	cp -a "${PROJECT_DIR}/${TEMPLATE_DIR}/"*.css "${WORK_DIR}/public/${ASSET_DIR}" > /dev/null
}

build_posts(){
	prepare_posts

	local index_html_file="${WORK_DIR}/public/index.html"
	local archive_html_file="${WORK_DIR}/public/archive.html"
	local feed_file="${WORK_DIR}/public/feed.rss"

	cat $(build_html_head "" "index") > "${index_html_file}"
	cat $(build_html_head "" "archive") > "${archive_html_file}"
	cat $(build_archive_head "") >> "${archive_html_file}"
	cat $(build_feed_head "") > "${feed_file}"

	local count=0
	while IFS='' read -r filepath; do
		count=$((count + 1))
		
		local temp_filename=${filepath%.*}
		local basename=${temp_filename##*/}
		local basename=${basename%.*}
		local url="${POST_URL}/${basename%.*}.html"
		local post_html_file="${WORK_DIR}/public/${url}"

		# post
		cat $(build_html_head "${temp_filename%.*}.meta" "post") > "${post_html_file}"
		cat $(build_post_head "${temp_filename%.*}.meta") >> "${post_html_file}"
		cat "${temp_filename%.*}.post.html" >> "${post_html_file}"
		cat $(build_post_foot "${temp_filename%.*}.meta") >> "${post_html_file}"
		cat $(build_html_foot "${temp_filename%.*}.meta") >> "${post_html_file}"

		#index
		if [[ $count -lt 6 ]]; then
			cat $(build_excerpt_head "${temp_filename%.*}.meta"  "${url}") >> "${index_html_file}"
			cat "${temp_filename%.*}.excerpt.html" >> "${index_html_file}"
			cat $(build_excerpt_foot "${temp_filename%.*}.meta"  "${url}") >> "${index_html_file}"
		fi

		cat $(build_archive_row "${temp_filename%.*}.meta" "${url}") >> "${archive_html_file}"

		#feed
		cat $(build_feed_item_head "${temp_filename%.*}.meta" "${url}") >> "${feed_file}"
		cat "${temp_filename%.*}.excerpt.html" >> "${feed_file}"
		cat $(build_feed_item_foot "" "") >> "${feed_file}"

	done < <(ls -t ${WORK_DIR}/tmp/*.post.html)

	cat $(build_html_foot "") >> "${index_html_file}"

	cat $(build_archive_foot "") >> "${archive_html_file}"
	cat $(build_html_foot "" "") >> "${archive_html_file}"	

	cat $(build_feed_foot "" "") >> "${feed_file}"	
}

# 
prepare_posts(){
	mkdir -p "${WORK_DIR}/public/posts"

	while IFS='' read -r filepath; do
		local filename=${filepath##*/}
		local temp_filename=$(slice_markdown "${filepath}")
		local post="${temp_filename}.post.html"
		local post_date=$(read_metadata "${temp_filename}.meta" "date")

		md2html "${temp_filename}.content" "${post}"
		md2html "${temp_filename}.excerpt" "${temp_filename}.excerpt.html"
		touch -d "${post_date}" $post

	done < <(ls ${PROJECT_DIR}/${POST_DIR}/*.md)
	echo 
}

########################################
# COMMANDS                             #
########################################
# output help text and exit
cmd_help() {
  cat << EOF
Usage:
    $SCRIPTNAME init project
        Create skeleton in project folder
    $SCRIPTNAME new [--static|-s] project
        create a new post
    $SCRIPTNAME build project target
        build site in target folder
EOF
  exit 0
}

cmd_init(){
	echo "Not Implemented"
	exit 1
}

cmd_new(){
	echo "Not Implemented"
	exit 1
}

# $1 project dir
# $2 target dir
cmd_build(){
	set_project_dir "${1}"
	local target_dir="${2}"

	read_project_config
	create_work_dir

	mkdir "${WORK_DIR}/public"
	mkdir "${WORK_DIR}/public/${POST_URL}"
	mkdir "${WORK_DIR}/tmp"

	copy_assets
	build_posts

	cp -rv "${WORK_DIR}/public/." "${target_dir}"
}

########################################
# MAIN                                 #
########################################

case "$1" in
  init|i)     shift; cmd_init "$@" ;;
  new|n)     shift; cmd_new "$@" ;;
  build|b)         shift; cmd_build "$@" ;;
  help|--help|-h|*) cmd_help "$@" ;;
esac

exit 0