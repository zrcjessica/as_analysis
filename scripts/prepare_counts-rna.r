suppressMessages(library(plyr))
suppressMessages(library(rmutil))
suppressMessages(library(ape))
suppressMessages(library(rtracklayer))
suppressMessages(library(dplyr))

args = commandArgs(trailingOnly = TRUE)
# import rna counts for this sample
rna = read.table(gzfile(args[1]), sep=" ", header=F, stringsAsFactors=F, col.names=c("chr", "start", "ref", "alt", "genotype", "ref.matches", "alt.matches", "errors"))
# import gq data for this sample
gq = read.table(gzfile(args[2]), sep="\t", header=T, col.names=c("CHROM", "POS", "REF", "ALT", "GQ"))
# import gene info from gencode
genes= as(readGFF(args[3]), "GRanges")
# what is the output directory prefix? note that it should have a trailing slash
output_dir = args[4]

# create unique rsID column for later merging with gq
rna$rsID = paste0(rna$chr, ":", rna$start, "_", rna$ref, "/", rna$alt)
# remove genotype col, since all rows should be heterozygotes already
rna$genotype = NULL

# process gq data
# create rsID column for later merging and get rid of other columns
gq$rsID = paste0(gq$CHROM, ":", gq$POS, "_", gq$REF, "/", gq$ALT)
gq$CHROM = NULL
gq$POS = NULL
gq$REF = NULL
gq$ALT = NULL
# generate the genotype.error column
gq$genotype.error = 10^{-(gq$GQ/10)}
# retain only the cols that we need
gq = gq[c("genotype.error", "rsID")]

# process allele specific counts
proc_counts= function(counts, genes){
  # load counts and plot proportions
  counts$N=rowSums(counts[,c("ref.matches","alt.matches")])
  counts$p= counts$ref.matches/counts$N
  
  # step 1 filter counts
  message("- Removing ", sum(counts$N < 10), " SNPs that have low read counts")
  counts= subset(counts, N >= 10)
  num_old_counts = nrow(counts)
  counts$end= counts$start
  counts= GRanges(counts)
  
  # step 2 add genes
  hits= findOverlaps(counts, genes, type = "within")
  names(counts) = NULL
  counts= as.data.frame(counts[queryHits(hits)])
  genes= as.data.frame(genes[subjectHits(hits)])
  counts$gene= genes$gene_id
  counts= counts[!duplicated(counts),]
  message("- Removed ", num_old_counts-nrow(counts), " SNPs that have don't overlap a gene")
  counts
}

# process rna count data, adding gene information
message("Processing rna counts of ", nrow(rna), " SNPs...")
rna = proc_counts(rna, genes)
# save memory by removing genes. it isn't needed anymore
rm(genes)

# add genotype.error from gq to rna by JOINing on common column rsID
message("Adding genotype error to ", nrow(rna), " RNA SNPs...")
rna = inner_join(rna, gq, by="rsID")
# save memory by removing gq, it isn't needed anymore
rm(gq)

# save the results to csv files
message("Writing ", nrow(rna), " final SNPs to file...\n")
rna_output = paste0(output_dir, "rna.csv")
write.csv(rna, rna_output, row.names = F)
system(paste("gzip", rna_output))

# if we got this far, we were probably successful
quit(status=0)