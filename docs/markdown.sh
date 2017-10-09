#!/bin/sh

./lpp.pl tex/preamble.tex       > build/preamble.tex
./lpp.pl tex/setup.tex          > build/setup.tex
./lpp.pl tex/configurations.tex > build/configuration.tex
./lpp.pl tex/csrs.tex           > build/csrs.tex
./lpp.pl tex/debug.tex          > build/debug.tex
./lpp.pl tex/external-if.tex    > build/external-if.tex
./lpp.pl tex/history.tex        > build/history.tex
./lpp.pl tex/introduction.tex   > build/introduction.tex
./lpp.pl tex/pipeline.tex       > build/pipeline.tex
./lpp.pl tex/product-brief.tex  > build/product-brief.tex
./lpp.pl tex/references.tex     > build/references.tex
./lpp.pl tex/resources.tex      > build/resources.tex

pandoc --default-image-extension=png -t markdown_github -o ../DATASHEET.md "RoaLogic_RV12_RISCV_Markdown.tex"
