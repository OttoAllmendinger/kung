.PHONY: all

PL=pdflatex
PLFLAGS=-shell-escape -halt-on-error -interaction=nonstopmode

pdf/Report.pdf: *.tex
	cp *.tex tmp/
	cd tmp; $(PL) $(PLFLAGS) Report.tex; $(PL) $(PLFLAGS) Report.tex
	cp tmp/Report.pdf pdf/

clean:
	rm -f tmp/*
