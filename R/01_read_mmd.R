# 01_read_mmd.R — leesfuncties voor GeoDMS mmd-exports (memory-mapped data)
#
# Een .mmd is een DIRECTORY met per attribuut een plat little-endian binair bestand
# (geen header) plus een 0Dictionary.dms die domein-range en attribuuttypen beschrijft.
# Strings staan als <naam> (indexparen, 2x uint64 per rij: [begin, eind) in bytes)
# met de karakterdata in <naam>.seq. Bool is bit-packed (1 bit per rij, LSB eerst).
#
# Waardetypen die niet uit de dictionary volgen (unit-referenties zoals /units/m2)
# staan in een expliciete mappingtabel; een file-size-check vangt elke mismatch af.

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
    n    = n
  )
}

# GeoDMS-type -> leesspecificatie. bytes = bytes per rij; what/size voor readBin.
.mmd_type_spec <- function(type) {
  # unit-referenties uit deze configuratie (waardetype per Units.dms / Classifications)
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
  # classificatie-referenties (WP4, Redev_ObjectTypes, UrbanisationK, ...) zijn uint8-domeinen
  if (grepl("^/(classifications|Classifications|Analyse)/", type)) {
    return(list(what = "integer", size = 1, bytes = 1, signed = FALSE))
  }
  NULL
}

.read_mmd_column <- function(dir_mmd, name, type, n) {
  spec <- .mmd_type_spec(type)
  if (is.null(spec)) { warning(sprintf("kolom %s: onbekend type %s, overgeslagen", name, type)); return(NULL) }
  path <- file.path(dir_mmd, name)
  if (!file.exists(path)) {
    # GeoDMS schrijft namen soms met andere case (bv. Site_ID vs site_id): case-insensitive zoeken
    cand <- list.files(dir_mmd, full.names = TRUE)
    hit <- cand[tolower(basename(cand)) == tolower(name)]
    if (!length(hit)) { warning(sprintf("kolom %s: bestand ontbreekt in mmd, overgeslagen", name)); return(NULL) }
    path <- hit[1]
  }

  fsz <- file.info(path)$size
  verwacht <- if (spec$what == "bool") ceiling(n / 8) else n * spec$bytes
  if (fsz != verwacht) {
    warning(sprintf("kolom %s: bestandsgrootte %d wijkt af van verwacht %d (type %s), overgeslagen",
                    name, fsz, verwacht, type))
    return(NULL)
  }

  con <- file(path, "rb"); on.exit(close(con))
  if (spec$what == "bool") {
    raw <- readBin(con, "raw", n = ceiling(n / 8))
    bits <- as.logical(rawToBits(raw))          # LSB eerst per byte
    return(bits[seq_len(n)])
  }
  if (spec$what == "string") {
    # Indexbestand: 2x uint64 per rij ([begin, eind) in bytes, TILE-LOKAAL); null = 2^64-1.
    # Lees als 4x uint32 en combineer (offsets << 2^53, dus exact representeerbaar in double).
    u <- readBin(con, "integer", n = 4L * n, size = 4)
    ofs <- bitwAnd_u32(u[seq(1, 4L * n, by = 2)]) + bitwAnd_u32(u[seq(2, 4L * n, by = 2)]) * 2^32
    begin <- ofs[seq(1, 2L * n, by = 2)]
    eind  <- ofs[seq(2, 2L * n, by = 2)]

    # .seq: header met tile-directory, dan per tile een (gepad) datasegment.
    # Header: uint64[0] = data_start (= lengte header = start tile 0); daarna per tile
    # (used, alloc, file_end) — de laatste tile heeft geen file_end (impliciet = bestandsgrootte).
    # Tiles zijn 65536 rijen (GeoDMS-tiling); gevalideerd tegen PerObject_Export_AMS_20260108.
    seqf <- paste0(path, ".seq")
    stopifnot(file.exists(seqf))
    seq_raw <- readBin(seqf, "raw", n = file.info(seqf)$size)
    hdr_u <- readBin(seq_raw[1:8], "integer", n = 2, size = 4)
    data_start <- bitwAnd_u32(hdr_u[1]) + bitwAnd_u32(hdr_u[2]) * 2^32
    hdr <- readBin(seq_raw[seq_len(data_start)], "integer", n = data_start / 4, size = 4)
    hdr64 <- bitwAnd_u32(hdr[seq(1, length(hdr), by = 2)]) + bitwAnd_u32(hdr[seq(2, length(hdr), by = 2)]) * 2^32
    tile_size <- 65536L
    n_tiles <- ceiling(n / tile_size)
    tile_start <- numeric(n_tiles)
    tile_start[1] <- data_start
    if (n_tiles > 1) for (t in seq_len(n_tiles - 1)) tile_start[t + 1] <- hdr64[1 + 3 * t]  # file_end van tile t-1 = start tile t
    stopifnot(length(hdr64) == 3 * n_tiles)  # 1 (data_start) + 3 per tile - 1 (laatste zonder eind) + 2 = 3*T

    seq_raw[seq_raw == as.raw(0)] <- as.raw(32)   # NULs (header/padding) -> spatie; posities verschuiven niet
    buf <- rawToChar(seq_raw)
    Encoding(buf) <- "latin1"   # 1 byte == 1 char, zodat substring op byte-offsets klopt
    tile_of <- (seq_len(n) - 1L) %/% tile_size
    is_null <- eind >= 2^63    # null-marker (2^64-1)
    out <- rep(NA_character_, n)
    ok <- !is_null
    out[ok] <- substring(buf, tile_start[tile_of[ok] + 1L] + begin[ok] + 1, tile_start[tile_of[ok] + 1L] + eind[ok])
    return(out)
  }
  if (spec$what == "uint64") {
    u <- readBin(con, "integer", n = 2L * n, size = 4)
    lo <- bitwAnd_u32(u[seq(1, 2L * n, by = 2)])
    hi <- bitwAnd_u32(u[seq(2, 2L * n, by = 2)])
    return(lo + hi * 2^32)                                 # BAG-nummers < 2^53: exact in double
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

# signed int32 -> unsigned waarde (als double)
bitwAnd_u32 <- function(x) ifelse(x < 0, x + 2^32, x)

#' Lees een GeoDMS mmd-directory in als data.table.
#' @param dir_mmd pad naar de .mmd-directory
#' @param cols optioneel: alleen deze kolommen (character); NULL = alles
read_mmd <- function(dir_mmd, cols = NULL) {
  d <- read_mmd_dictionary(dir_mmd)
  if (!is.null(cols)) d <- d[tolower(name) %in% tolower(cols)]
  out <- list()
  for (i in seq_len(nrow(d))) {
    v <- .read_mmd_column(dir_mmd, d$name[i], d$type[i], d$n[i])
    if (is.null(v)) next
    if (is.list(v)) {  # puntkolom -> twee kolommen
      out[[paste0(d$name[i], "_x")]] <- v$x
      out[[paste0(d$name[i], "_y")]] <- v$y
    } else out[[d$name[i]]] <- v
  }
  setDT(out)[]
}
