FIELDS = ['url1','url2','seg1','seg2','aligner']
DEFERRED = False
DEFERRED_FIELDS = []
BIFIXER = False
BIFIXER_FIELDS = []
AGGRESSIVE_DEDUP = ""
BICLEANER = False
BICLEANER_MODEL = ""
BICLEANER_FIELDS = []
BICLEANER_THRESHOLD = 0.0
ELRC = False
ELRC_FIELDS = []
TMX = False
DEDUPED = False
FILES = ["sent", "raw"]

if 'deferredCrawling' in crawling and crawling['deferredCrawling']:
	DEFERRED = True
	DEFERRED_FIELDS = ['deferredseg1','checksum1','deferredseg2','checksum2']
if 'bifixer' in config and config['bifixer']:
	BIFIXER = True
	BIFIXER_FIELDS = ['bifixerhash','bifixerscore']
if 'aggressiveDedup' in config and config['aggressiveDedup']:
	AGGRESSIVE_DEDUP = '--aggressive_dedup'
if 'bicleaner' in config:
	BICLEANER = True
	BICLEANER_MODEL = config['bicleaner']
	BICLEANER_FIELDS = ['bicleaner']
if 'bicleanerThreshold' in config:
	BICLEANER_THRESHOLD = config['bicleanerThreshold']
if 'elrc' in config and config['elrc']:
	ELRC = True
	ELRC_FIELDS = ['lengthratio','numTokensSL','numTokensTL']
if 'tmx' in config and config['tmx']:
	TMX = True
	FILES.append('not-deduped.tmx')
if 'deduped' in config and config['deduped']:
	FILES.append('deduped.tmx')
	FILES.append('txt')

BEFORE_ELRC_FIELDS = FIELDS + DEFERRED_FIELDS + BIFIXER_FIELDS + BICLEANER_FIELDS
TMX_FIELDS = BEFORE_ELRC_FIELDS + ELRC_FIELDS
BIFIXER_HASH_COLUMN = BEFORE_ELRC_FIELDS.index('bifixerhash')
BIFIXER_SCORE_COLUMN = BIFIXER_HASH_COLUMN + 1

BEFORE_ELRC_FIELDS = ','.join(BEFORE_ELRC_FIELDS)
TMX_FIELDS = ','.join(TMX_FIELDS)

rule cleaning_all:
	input: expand("{permanent}/{target}/{lang1}-{lang2}.{file}.xz", permanent=PERMANENT, target=TARGETS, file=FILES) 

# TODO: add deferred
rule bifixer:
	input: f'{TRANSIENT}/{{target}}/segalign.xz'
	output: temp(f'{TRANSIENT}/{{target}}/bifixer')
	shell: '''
		xzcat -T 0 -f {input} \
			| python3 {BITEXTOR}/bifixer/bifixer/bifixer.py -q - - {LANG1} {LANG2} {AGGRESSIVE_DEDUP} \
			| LC_ALL=C sort -t $'\t' -k{BIFIXER_HASH_COLUMN},{BIFIXER_HASH_COLUMN} -k{BIFIXER_SCORE_COLUMN},{BIFIXER_SCORE_COLUMN}nr -T {TMPDIR} --compress-program=gzip -n -r \
			> {output}
		'''

rule bicleaner:
	input: bifixer=rules.bifixer.output, model=BICLEANER_MODEL
	output: temp(f'{TRANSIENT}/{{target}}/bicleaner')
	shell: '''
		slang=$(egrep "source_lang" {input.model} | cut -d " " -f 2)
		if [ "$slang" == "{LANG1}" ]; then
	 		cat {input.bifixer} \
				| {BITEXTOR}/preprocess/bin/cache -k {BIFIXER_HASH_COLUMN} python3 {BITEXTOR}/bicleaner/bicleaner/bicleaner_classifier_lite.py --score-only -q - - {params.model} \
				| paste <(cat {input.bifixer}) - \
				| python3 {BITEXTOR}/bitextor-filterbicleaner.py --threshold {BICLEANER_THRESHOLD} \
				> {output}
		else
			cat {input.bifixer} \
				| awk ' BEGIN {{FS="\t"; OFS="\t"}} {{ t = $3; $3 = $4; $4 = t; print;}} ' \
				| {BITEXTOR}/preprocess/bin/cache -k {BIFIXER_HASH_COLUMN} python3 {BITEXTOR}/bicleaner/bicleaner/bicleaner_classifier_lite.py --score-only -q - - {params.model} \
				| paste <(cat {input.bifixer}) - \
				| python3 {BITEXTOR}/bitextor-filterbicleaner.py --threshold {BICLEANER_THRESHOLD} \
				> {output}
		fi
		'''

rule elrc:
		input: elrc_input
		output: temp(f'{TRANSIENT}/{{target}}/elrc')
		shell: '''
			if [ "{ELRC} == cat {input} \
				| {BITEXTOR}/bitextor/elrc/filtering.py -c "{BEFORE_ELRC_FIELDS}" -s \
				| xz -T 0 > {output}
			'''

rule sents:
		input: expand("{transient}/{target}/elrc", transient=TRANSIENT, target=TARGETS)
		output: f'{PERMANENT}/{LANG1}-{LANG2}.sent.xz'
		shell: 'cat {input} | xz -T 0 -c > {output}'