# 01_read_mmd.R — reader functions for GeoDMS mmd exports (memory-mapped data)
#
# An .mmd is a DIRECTORY with one flat little-endian binary file per attribute
# (no header) plus a 0Dictionary.dms describing the domain range and attribute types.
# Strings are stored as <name> (index pairs, 2x uint64 per row: [begin, end) in bytes)
# with the character data in <name>.seq. Bool is bit-packed (1 bit per row, LSB first).
#
# Value types that do not follow from the dictionary (unit references such as /units/m2)
# are held in an explicit mapping table; a file-size check catches any mismatch.

read_mmd_dictionary <- function(dir_mmd) {
  dict_file <- file.path(dir_mmd, "0Dictionary.dms")
  stopifnot(file.exists(dict_file))
  txt <- readLines(dict_file, warn = FALSE)

  n <- as.integer(sub(".*\\[0, *([0-9]+)\\).*", "\\1", grep("Range", txt, value = TRUE)[1]))

  attr_lines <- grep("^\\s*attribute<", txt, value = TRUE)
  m <- regmatches(attr_lines, regexec("attribute<([^>]+)>\\s+([A-Za-z0-9_]+)\\(", attr_lines))
  data.table(
    name = vapply(m, `[`, "", 3L),
    type = vapply(m, `[`, "", 2L),
    # polygons ('(., poly)') are variable-length sequences (index file + .seq with the
    # coordinate series); the index file happens to be the same size as a point column
    # (16 bytes/row) and would be read as garbage coordinates -> skip explicitly
    poly = grepl("\\(\\s*\\.\\s*,\\s*poly\\s*\\)", attr_lines),
    n    = n
  )
}

# GeoDMS type -> read specification. bytes = bytes per row; what/size for readBin.
.mmd_type_spec <- function(type) {
  # unit references from this configuration (value type per Units.dms / Classifications)
  ref_map <- list(
    "/units/m2"                = list(what = "double",  size = 8, bytes = 8),
    "/units/eur"               = list(what = "double",  size = 8, bytes = 8),
    "/units/eur_m2"            = list(what = "double",  size = 8, bytes = 8),
    "/units/yr"                = list(what = "integer", size = 2, bytes = 2, signed = FALSE),
    "/geography/rdc"           = list(what = "double",  size = 8, bytes = 16, point = TRUE),
    "/geography/rdc_25m"       = list(what = "integer", size = 4, bytes = 8, point = TRUE),
    "/geography/rdc_100m"      = list(what = "integer", size = 4, bytes = 8, point = TRUE)
  )
  base_map <- list(
    "Float32" = list(what = "numeric", size = 4, bytes = 4),
    "Float64" = list(what = "double",  size = 8, bytes = 8),
    "Int32"   = list(what = "integer", size = 4, bytes = 4),
    "UInt32"  = list(what = "integer", size = 4, bytes = 4, unsigned32 = TRUE),
    "Int16"   = list(what = "integer", size = 2, bytes = 2),
    "UInt16"  = list(what = "integer", size = 2, bytes = 2, signed = FALSE),
    "UInt8"   = list(what = "integer", size = 1, bytes = 1, signed = FALSE),
    "UInt64"  = list(what = "uint64",  size = 4, bytes = 8),
    "UPoint"  = list(what = "integer", size = 4, bytes = 8, point = TRUE),
    "Bool"    = list(what = "bool",    size = 1, bytes = 0.125),
    "String"  = list(what = "string",  size = 8, bytes = 16)
  )
  if (type %in% names(base_map)) return(base_map[[type]])
  if (type %in% names(ref_map))  return(ref_map[[type]])
  # classification references (WP4, Redev_ObjectTypes, UrbanisationK, ...) are uint8 domains
  if (grepl("^/(classifications|Classifications|Analyse)/", type)) {
    return(list(what = "integer", size = 1, bytes = 1, signed = FALSE))
  }
  NULL
}

.read_mmd_column <- function(dir_mmd, name, type, n) {
  spec <- .mmd_type_spec(type)
  if (is.null(spec)) { warning(sprintf("column %s: unknown type %s, skipped", name, type)); return(NULL) }
  path <- file.path(dir_mmd, name)
  if (!file.exists(path)) {
    # GeoDMS sometimes writes names with different case (e.g. Site_ID vs site_id): search case-insensitively
    cand <- list.files(dir_mmd, full.names = TRUE)
    hit <- cand[tolower(basename(cand)) == tolower(name)]
    if (!length(hit)) { warning(sprintf("column %s: file missing in mmd, skipped", name)); return(NULL) }
    path <- hit[1]
  }

  fsz <- file.info(path)$size
  # Bool is bit-packed in 32-bit words, so the file holds ceiling(n/32)*4 bytes. For the export of
  # July (8,700,061 rows) that equalled ceiling(n/8) by chance; the export of 25-09 (9,185,609 rows)
  # has two padding bytes more, and a byte-based check skipped every bool column.
  expected <- if (spec$what == "bool") ceiling(n / 32) * 4 else n * spec$bytes
  if (fsz != expected) {
    warning(sprintf("column %s: file size %d differs from expected %d (type %s), skipped",
                    name, fsz, expected, type))
    return(NULL)
  }

  con <- file(path, "rb"); on.exit(close(con))
  if (spec$what == "bool") {
    raw <- readBin(con, "raw", n = ceiling(n / 8))
    bits <- as.logical(rawToBits(raw))          # LSB first per byte
    return(bits[seq_len(n)])
  }
  if (spec$what == "string") {
    # Index file: 2x uint64 per row ([begin, end) in bytes, TILE-LOCAL); null = 2^64-1.
    # Read as 4x uint32 and combine (offsets << 2^53, so exactly representable in double).
    u <- readBin(con, "integer", n = 4L * n, size = 4)
    ofs <- bitwAnd_u32(u[seq(1, 4L * n, by = 2)]) + bitwAnd_u32(u[seq(2, 4L * n, by = 2)]) * 2^32
    begin <- ofs[seq(1, 2L * n, by = 2)]
    end   <- ofs[seq(2, 2L * n, by = 2)]

    # .seq: header of 3 uint64 per tile — (start_in_file, used_bytes, alloc_bytes) — followed by the
    # tile data segments. NOTE: the segments appear in ARBITRARY order in the file
    # (multithreaded writes); start_t is therefore the only reliable position information.
    # Tiles are 65536 rows (GeoDMS tiling); index offsets are tile-local from start_t.
    # Validated against PerObject_Export_AMS_20260108 and PerObject_Export_Nederland_20260710.
    seqf <- paste0(path, ".seq")
    stopifnot(file.exists(seqf))
    seq_raw <- readBin(seqf, "raw", n = file.info(seqf)$size)
    tile_size <- 65536L
    n_tiles <- as.integer(ceiling(n / tile_size))
    hdr_len <- 3L * n_tiles * 8L
    stopifnot(length(seq_raw) >= hdr_len)
    hdr <- readBin(seq_raw[seq_len(hdr_len)], "integer", n = hdr_len / 4, size = 4)
    hdr64 <- bitwAnd_u32(hdr[seq(1, length(hdr), by = 2)]) + bitwAnd_u32(hdr[seq(2, length(hdr), by = 2)]) * 2^32
    tile_start <- hdr64[seq(1, 3L * n_tiles, by = 3)]
    tile_alloc <- hdr64[seq(3, 3L * n_tiles, by = 3)]
    stopifnot(all(tile_start + tile_alloc <= length(seq_raw)))

    seq_raw[seq_raw == as.raw(0)] <- as.raw(32)   # NULs (header/padding) -> space; positions do not shift
    buf <- rawToChar(seq_raw)
    Encoding(buf) <- "latin1"   # 1 byte == 1 char, so substring on byte offsets is correct
    tile_of <- (seq_len(n) - 1L) %/% tile_size
    is_null <- end >= 2^63    # null marker (2^64-1)
    out <- rep(NA_character_, n)
    ok <- !is_null
    out[ok] <- substring(buf, tile_start[tile_of[ok] + 1L] + begin[ok] + 1, tile_start[tile_of[ok] + 1L] + end[ok])
    return(out)
  }
  if (spec$what == "uint64") {
    u <- readBin(con, "integer", n = 2L * n, size = 4)
    lo <- bitwAnd_u32(u[seq(1, 2L * n, by = 2)])
    hi <- bitwAnd_u32(u[seq(2, 2L * n, by = 2)])
    return(lo + hi * 2^32)                                 # BAG numbers < 2^53: exact in double
  }
  if (isTRUE(spec$point)) {
    v <- readBin(con, spec$what, n = 2L * n, size = spec$size)
    return(list(x = v[seq(1, 2L * n, by = 2)], y = v[seq(2, 2L * n, by = 2)]))
  }
  v <- readBin(con, spec$what, n = n, size = spec$size,
               signed = if (!is.null(spec$signed)) spec$signed else TRUE)
  if (isTRUE(spec$unsigned32)) v <- ifelse(v < 0, v + 2^32, v)
  v
}

# signed int32 -> unsigned value (as double)
bitwAnd_u32 <- function(x) ifelse(x < 0, x + 2^32, x)

#' Read a GeoDMS mmd directory as a data.table.
#' @param dir_mmd path to the .mmd directory
#' @param cols optional: only these columns (character); NULL = everything
read_mmd <- function(dir_mmd, cols = NULL) {
  d <- read_mmd_dictionary(dir_mmd)
  if (!is.null(cols)) d <- d[tolower(name) %in% tolower(cols)]
  out <- list()
  for (i in seq_len(nrow(d))) {
    if (isTRUE(d$poly[i])) next   # polygon columns: not readable as a table column (see read_mmd_dictionary)
    v <- .read_mmd_column(dir_mmd, d$name[i], d$type[i], d$n[i])
    if (is.null(v)) next
    if (is.list(v)) {  # point column -> two columns
      out[[paste0(d$name[i], "_x")]] <- v$x
      out[[paste0(d$name[i], "_y")]] <- v$y
    } else out[[d$name[i]]] <- v
  }
  setDT(out)[]
}
