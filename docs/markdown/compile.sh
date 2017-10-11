#!/bin/bash

cd ../tex

# Pre-process LaTeX Source
for file in *.tex
do
 ../markdown/lpp.pl $file > ../markdown/$file
done

cd ../markdown

# Generate new Markdown
pandoc --atx-headers --default-image-extension=png -t markdown_github -B frontmatter.md -o ../../DATASHEET.md "RoaLogic_RV12_RISCV_Markdown.tex"
