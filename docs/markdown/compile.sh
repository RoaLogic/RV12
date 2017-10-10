#!/bin/bash

topfile="RoaLogic_RV12_RISCV_Markdown"

# Run from markdown directory only
curdir=${PWD##*/}

if [ "$curdir" != "markdown" ]
then
	echo "Must run from markdown directory"
    exit
fi

# Pre-process LaTeX Source
for entry in ../tex/*.tex
do
  	base="${entry##*/}"
	./lpp.pl $entry > $base
done


# Generate new Markdown
cd ..
pandoc 	--atx-headers \
		--base-header-level=2 \
		--number-sections \
		--default-image-extension=png \
		--file-scope \
		--toc \
		--toc-depth=1 \
		-t markdown_github \
		-B markdown/frontmatter.md \
		-o ../DATASHEET.md \
		$topfile.tex

cd markdown

# Remove Preprocessed LaTeX source
rm *.tex
