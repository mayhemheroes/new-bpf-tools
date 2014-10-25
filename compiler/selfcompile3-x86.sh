if ! test -e wcc
then
	echo "please compile the standalone wcc command via ./build-wcc.sh"
	exit 1
fi

if ! test -e wcc3
then
        echo "please compile phase 3 (wcc2) via selfcompile"
fi


./wcc3 -DWCC -g -o wcc4 tokenizer.c general.c tokens.c hashtable.c diagnostics.c main.c optimize.c tree.c preprocess.c escapes.c typeof.c codegen_x86.c parser.c constfold.c global_initializer.c
./wcc3 -g -o wcc4b tokenizer.c general.c tokens.c hashtable.c diagnostics.c main.c optimize.c tree.c preprocess.c escapes.c typeof.c codegen_x86.c parser.c constfold.c global_initializer.c
