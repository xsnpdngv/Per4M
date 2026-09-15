# === From environment ===
NAME ?= perf
SUB  ?=

# === Configuration ===
CALLGRAPH_NODE_THRES_PCT = 0.5 # eliminate nodes below this threshold [default: 0.5]
CALLGRAPH_EDGE_THRES_PCT = 0.1 # eliminate edges below this threshold [default: 0.1]
CALLGRAPH_THEME_SKEW = 0.05    # skew the colorization curve,
                               # Values < 1.0 give more variety to lower percentages
                               # Values > 1.0 give less variety to lower percentages

FLAMEGRAPH_DIR ?= $(HOME)/git/FlameGraph

DATE = $(shell date +%Y-%m-%d)

SRC_MD     = README.md
DOC_PDF    = Per4M_v1.0.pdf
PERF_DATA  = perf.data
PERF_SCRIPT = perf.script
PERF_SCRIPT_FLT = perf.script.flt

CALL_DOT   = "$(NAME)_callgraph_$(DATE).dot"
CALL_PDF   = "$(NAME)_callgraph_$(DATE).pdf"
FLAME_SVG  = "$(NAME)_flamegraph_$(DATE).svg"


# === Options ===
PANDOC_OPTS = \
    -V papersize:A4 \
    -V documentclass=article \
    -V geometry:margin=1in \
    -V colorlinks \
    --toc \
    --toc-depth=2 \
    --pdf-engine=xelatex \
    -V monofont='Ubuntu Mono'

GPROF_OPTS = \
    --format=perf \
    --strip --wrap \
    --skew=$(CALLGRAPH_THEME_SKEW) \
    --color-nodes-by-selftime \
    --node-thres=$(CALLGRAPH_NODE_THRES_PCT) \
    --edge-thres=$(CALLGRAPH_EDGE_THRES_PCT)

DOT_OPTS = \
    -Tpdf \
    -Glabel="$(NAME) $(DATE)" \
    -Gfontsize=24 \
    -Glabelloc=top 


# === Default target ===
all: callgraph flamegraph


# === Documentation ===
doc: $(DOC_PDF)

$(DOC_PDF): $(SRC_MD)
	pandoc $< $(PANDOC_OPTS) -o $@ 


# === Perf script ===
# perf is not available here; $(PERF_SCRIPT) is produced on the host
# (per4m.sh does this automatically from $(PERF_DATA)).
$(PERF_SCRIPT):
	@echo "❌ $@ not found."; \
	echo "   Record and convert on the host:"; \
	echo "     perf record --call-graph lbr <command>"; \
	echo "     perf script > $@"; \
	exit 1

$(PERF_SCRIPT_FLT): $(PERF_SCRIPT)
	( sed 's/@plt//g' \
	| grep -v ' __libc_start_main\+' \
	| grep -v ' _start\+' \
	| grep -v ' main\+' \
	) < $< > $@


# === Callgraph ===
cg callgraph: $(CALL_PDF)

$(CALL_DOT): $(PERF_SCRIPT_FLT)
	( gprof2dot $(GPROF_OPTS) \
	) < $< > $@

$(CALL_PDF): $(CALL_DOT)
	( dot $(DOT_OPTS) \
	) < $< > $@


# === Flamegraph ===
fg flamegraph: $(FLAME_SVG)

$(FLAME_SVG): $(PERF_SCRIPT_FLT)
	( $(FLAMEGRAPH_DIR)/stackcollapse-perf.pl \
	| $(FLAMEGRAPH_DIR)/flamegraph.pl \
	    --title "$(NAME) $(DATE)" \
	    --subtitle "$(SUB)" \
	) < $< > $@


# === Cleanup ===
clean:
	rm -f *.doc *.flt *.svg *.dot *.pdf


# === Rebuild everything ===
rebuild: clean all

.PHONY: all doc cg callgraph fg flamegraph clean rebuild
