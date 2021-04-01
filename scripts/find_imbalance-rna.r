suppressMessages(library(plyr))
suppressMessages(library(rmutil))
suppressWarnings(suppressMessages(library(rtracklayer)))
suppressMessages(library(dplyr))
suppressMessages(library(tools))

args = commandArgs(trailingOnly = TRUE)
# args[1] should be the path to a file in which the allele.imbalance function is defined: allele.imbalance(rna, rna.err)
source(args[1])
# import rna counts, which should be ready for input into allele_imbalance.r
rna = read.csv(gzfile(args[2]))
# import gene info from gencode
if (file_ext(args[3]) == "gtf" | file_ext(args[3]) == "gff") {
  targets = readGFF(args[3])
  add_genes = TRUE
} else if (file_ext(args[3]) == "bed" | file_ext(args[3]) == "narrowPeak") {
  add_genes = FALSE
} else {
  stop("Aborting! Targets file extension is not supported. Must be one of gtf, gff, bed, or narrowPeak.")
}

# calculate error rates
err.rate = function(ref, alt, err){
  rate = (sum(err))/sum(ref+alt+err)
  rate*(3/2)
}

# get rna errors for allele_imbalance.r
message("Calculating rna error rates...")
rna.err = err.rate(rna$ref.matches, rna$alt.matches, rna$errors)

# NOW, we can finally call allele.imbalance()
# note that rna is a data frame that need to have these columns:
# 	ref.matches (ie ref_allele_count),
# 	N (total allele count - ref+alt),
# 	genotype.error (ie 10^(-GQ/10)),
# 	rsID (<chr>:<pos>_<allele1>/<allele2>),
# 	target (name of gene/peak that this SNP appears in, as provided by gencode),
#   start (position of SNP)
rna = rna[c('ref.matches', 'N', 'genotype.error', 'rsID', 'target', 'start')]
# call allele_imbalance and store the result in res
message("Calling allele.imbalance on ", nrow(rna), " SNPs...")
res = as.data.frame(allele.imbalance(rna, rna.err))

# rename col 'd' to 'a', since it represents estimates of allelic imbalance
colnames(res)[which(names(res) == "d")] = "a"
if (add_genes) {
  # convert gene col from type factor to type char so dplyr is happy
  res$gene = as.character(res$gene)
  # add gene names to res. it only has gene_id right now
  message("Adding gene names to ", nrow(res)," genes...")
  res = left_join(res, unique(genes[, c("gene_name", "gene_id")]), by = c("gene"="gene_id"))
}
message("Writing ", nrow(res), " targets to file...\n")
write.csv(res, stdout(), row.names = F, quote = F)