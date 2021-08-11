set -eu

indb="$1"
outdir="$2"
pagesPerServerChunk=${pagesPerServerChunk:-1}
cpu=$(getconf _NPROCESSORS_ONLN)

find "$outdir" -type f -name 'db.sqlite3.*' -delete

# http://phodd.net/gnu-bc/bcfaq.html#bashlog
log(){ local x=$1 n=2 l=-1;if [ "$2" != "" ];then n=$x;x=$2;fi;while((x));do let l+=1 x/=n;done;echo $l; }

# for chunked mode, we need to know the database size in bytes beforehand
bytes="$( stat --printf="%s" "$indb" )"
# set request chunk size to match page size
pageSize="$( sqlite3 "$indb" 'pragma page_size' )"
requestChunkSize=$pageSize
# set chunk size to a multiple of the `pragma page_size`)
pagesPerServerChunk=1
serverChunkSize=$(( $pagesPerServerChunk * $pageSize ))
# calculate suffix size
chunks=$(( ($bytes+$serverChunkSize-1) / $serverChunkSize ))
suffixLength="$( log 10 $chunks )"
suffixLength=$(( $suffixLength + 1 ))

# split the database in chunks, and compress each chunk individually
# the files will be called:
# $outdir/db.sqlite3.$suffix
# $outdir/db.sqlite3.$suffix.gz
# $outdir/db.sqlite3.$suffix.br
# This is useful e.g. with the gzip_static and brotli_static directives in nginx
# https://nginx.org/en/docs/http/ngx_http_gzip_static_module.html#gzip_static
# https://github.com/google/ngx_brotli#brotli_static
split "$indb" --bytes=$serverChunkSize "$outdir/db.sqlite3." --suffix-length=$suffixLength --numeric-suffixes
find "$outdir" -type f -regex 'db\.sqlite3\.[0-9]+$' | xargs -P$cpu -I{} sh -c 'f="{}"; gzip --keep --best "$f"; brotli --keep --best "$f"'


# write a json config
echo '
{
    "serverMode": "chunked",
    "requestChunkSize": '$requestChunkSize',
    "databaseLengthBytes": '$bytes',
    "serverChunkSize": '$serverChunkSize',
    "urlPrefix": "db.sqlite3.",
    "suffixLength": '$suffixLength'
}
' > "$outdir/config.json"
