#!/bin/bash

svn_ser=`cat settings.conf | grep 'svn-cer' | awk -F= '{print $2}' | sed -e 's/^ *//' -e 's/ *$//'`
tag_url=`cat settings.conf | grep 'tag-url' | awk -F= '{print $2}' | sed -e 's/^ *//' -e 's/ *$//'`

tag=$(svn ls $svn_ser "${tag_url}"
	| sort -r | sed -n '1p' | sed 's/\///')

tag=${1-$tag}

tag_root=`cat settings.conf | grep 'tag-arch-root' | awk -F= '{print $2}' | sed -e 's/^ *//' -e 's/ *$//'`
arch_file="$tag_root/$tag.7z"

if [ -e "$arch_file" ]; then
	echo "Archive file \`$arch_file' already exists."
else
	echo "Start to get $tag"

	work_path=`cat settings.conf | grep 'work-root' | awk -F= '{print $2}' | sed -e 's/^ *//' -e 's/ *$//'`
	work_path=${work_path}/`cat settings.conf | grep 'tag-path' | awk -F= '{print $2}' | sed -e 's/^ *//' -e 's/ *$//'`
	mkdir -p ${work_path}

	rm -rf "${work_path}/${tag}"
	svn export $svn_ser "${tag_url}/${tag}" "${work_path}/${tag}"

	rm -rf "${work_path}/${tag}.7z"
	7z a "${work_path}/${tag}.7z" "${work_path}/${tag}"

	esudo cp "${work_path}/${tag}.7z" "${tag_root}"

	sudo mail-maker.pl -s pack-for-tag -f TAG=${tag}
fi
