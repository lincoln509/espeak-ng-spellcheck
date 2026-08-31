#!/bin/bash
cdate=$(date +'%F_%H-%M')
# set default language
if [ "$1" == "" ]; then
lang="lv"
else
lang=$1
fi

spellfile="${lang}_spelling_$cdate.txt"

# Répertoire de ce script, pour appeler winning-rule-lines.py et
# show-unused-lines.py par chemin absolu plutôt que de dépendre de $PATH.
scriptdir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# NOTE (2026) : espeak-ng a migré vers CMake, autotools (autogen.sh/
# configure/make à la racine) n'existe plus. On distingue donc :
#   - espeak_src   : racine du dépôt source (dictsource/, ht_rules...)
#   - espeak_build : dossier de build CMake (binaire + espeak-ng-data compilés)
espeak_src=~/code/espeak-ng
espeak_build=~/code/espeak-ng/build

function compile {
  sdir=$(pwd)
  export ESPEAK_DATA_PATH=$espeak_build/
  export LD_LIBRARY_PATH=$espeak_build/src/
  cmake --build "$espeak_build" >/dev/null
  cd "$espeak_src/dictsource"
  cp ${lang}_rules $sdir/${lang}_rules_$cdate
  cp ${lang}_list $sdir/${lang}_list_$cdate
  "$espeak_build/src/espeak-ng" --compile-debug=$lang
  cd $sdir
  echo "--------------"
}

function getprevfile {
  prevfile=$(find -name "${lang}_spelling*.txt" 2>/dev/null|cut -b3-|grep -v diff|tail -n1)
  echo "prevfile: '$prevfile'"
  if [ -z "$prevfile" ]; then
    prevfile="${lang}_spelling.txt"
    touch $prevfile
  fi
}

getprevfile

# Handle previous spelling file
if [ -f "$prevfile" ]; then
  read -r -p "Delete previous spelling file "$prevfile" [y/N]?" response
  response=${response,,} # tolower
  if [[ $response =~ ^(y|yes) ]]; then
    rm -f $prevfile
    getprevfile
  fi
  echo "$prevfile will be used as reference spelling file"
fi

# Start computing
echo "compiling espeak-ng..."
compile

echo "runnning espeak-ng spelling..."
"$espeak_build/src/espeak-ng" -v$lang -x -q -f $lang-words.txt > $spellfile

echo "making spelling diff file..."
diff -y --suppress-common-lines $prevfile $spellfile > ${lang}_spelling-diff.txt

echo "running espeak-ng... rules"
"$espeak_build/src/espeak-ng" -v$lang -X -q -f $lang-words.txt > ${lang}_rule-results.txt

echo "running winning-rule-lines.py..."
cat ${lang}_rule-results.txt | python3 "$scriptdir/winning-rule-lines.py" > ${lang}_winning-rule-lines.txt

echo "aggregating winning results for winning lines..."
cat ${lang}_winning-rule-lines.txt | awk '{print $1}' | sort -nu > ${lang}_winning-lines.txt
cat ${lang}_winning-rule-lines.txt | awk '{print $1}' | sort| uniq -c| sort -nr > ${lang}_winning-lines-count.txt
echo "" > lines.tmp
linecount=$(wc -l $espeak_src/dictsource/${lang}_rules |awk '{print $1}')
for i in $(seq 1 $linecount); do
  echo $i >> lines.tmp
done

echo "making list of unused lines file..."
diff -y lines.tmp ${lang}_winning-lines.txt|awk '{print $1"\t"$2}' > ${lang}_unused-lines.txt

echo "Generating content of unused lines..."
python3 "$scriptdir/show-unused-lines.py" ${lang}_rules_$cdate ${lang}_unused-lines.txt > ${lang}_unused-lines-content.txt
echo "Done"
