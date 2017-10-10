#!/bin/sh

./lpp.pl tex/preamble.tex          > build/preamble.tex
./lpp.pl tex/setup.tex             > build/setup.tex
./lpp.pl tex/01-product-brief.tex  > build/01-product-brief.tex
./lpp.pl tex/02-introduction.tex   > build/02-introduction.tex
./lpp.pl tex/03-pipeline.tex       > build/03-pipeline.tex
./lpp.pl tex/04-configurations.tex > build/04-configurations.tex
./lpp.pl tex/05-csrs.tex           > build/05-csrs.tex
./lpp.pl tex/06-external-if.tex    > build/06-external-if.tex
./lpp.pl tex/07-debug.tex          > build/07-debug.tex
./lpp.pl tex/08-resources.tex      > build/08-resources.tex
./lpp.pl tex/09-references.tex     > build/09-references.tex
./lpp.pl tex/10-history.tex        > build/10-history.tex

pandoc --default-image-extension=png -t markdown_github -o ../DATASHEET.md "RoaLogic_RV12_RISCV_Markdown.tex"
