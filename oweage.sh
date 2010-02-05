#!/bin/bash

exec 3<&1
exec 1<&-
exec 1> /dev/null

function show_help
{
    cat 1>&2 << "EOF"
Useage:
    oweage [OPTIONS] [ACTION]

OPTIONS
  -v  N
     Set verbosity level to N, normal crap is level 1.
  -d  database
     Specify the database to use. Default is $HOME/.oweage_db

ACTION
  -a  lender dollars[.cents] debtor1 ... debtorN
     Add new oweage.
  -b  name
     Show a person's overall balance. Positive means s/he is owed money.
  -s  lender [debtor1 ... debtorN]
     Search oweages, all terms must match.
  -r  regex
     Search oweages by matching a regular expression to the reason field.
EOF
    return 1
}

tmp1=`tempfile`
tmp2=`tempfile`
verbose_level=1
db="${HOME}/.oweage_db"

trace ()
{
    if [ "$1" -le "$verbose_level" ]
    then
        shift
        echo "$@" 1>&3
    fi
}

unformat_amt ()
{
    local amt x y
    trace 4 "unformat_amt ($1)"

    amt=(`echo "$1" | sed -e 's/^\$\?\([0-9]*\)\.\?\([0-9]*\)$/\1 \2/'`)
    x=${amt[0]}
    y=${amt[1]}

    trace 4 "$x $y"

    # Sanity checking
    if [ "${#y}" -gt 2 ]
    then
        trace 1 "You specified too many pennies!" 3>&2
        return 1
    fi

    # Zero-fill y
    while [ "${#y}" -lt 2 ]
    do
        y="${y}0"
    done

    echo "$x$y"
}

format_amt ()
{
    local x y
    x=$(($1 / 100))
    if [ $1 -ge 0 ] ; then
        y=$(($1 % 100))
    else
        y=$((- $1 % 100))
    fi

    printf '$%d.%02d\n' $x $y
}

read_oweage ()
{
    local token
    if ! read -a token
    then
        return 1
    fi
    lender=${token[0]}
    amt=${token[1]}
    debtors=(${token[@]:2})
    read
    reason="$REPLY"
}

show_oweage ()
{
    trace 1 "$lender `format_amt $amt` ${debtors[@]}"
    trace 1 "Reason: $reason"
}

match_lender ()
{
    test "$lender" = "$name"
}

match_cdr ()
{
    local str
    for str in ${@:2}
    do
        expr match "$str" "$1" && return 0
    done
    return 1
}

update_balances ()
{
    local found x y name amt
    name=$1
    amt=$2
    found=0
    while read x y
    do
        if [ "$x" = "$name" ]
        then
            y=$(($y + $amt))
            found=1
        fi
        echo $x $y >>$tmp2
    done <$tmp1

    if [ 0 -eq $found ]
    then
        echo $name $amt >>"$tmp2"
    fi
    mv "$tmp2" "$tmp1"
}

print_balances ()
{
    local x y
    while read x y
    do
        echo $x `format_amt "$y"`
    done
}

match_array ()
{
    local x y matchp
    # sarr - array searching
    # marr - array to match
    for x in ${marr[@]}
    do
        matchp=0
        for y in ${sarr[@]}
        do
            if expr "$x" : "$y"
            then
                matchp=1
            fi
        done

        test $matchp -eq 0 && return 1
    done
    return 0
}

add_oweage ()
{
    local db lender amt debtors reason
    db="$1"
    lender="$2"
    amt=`unformat_amt $3` || return 1
    debtors=(${@:4})

    trace 4 "db: $db"
    trace 4 "lender: $lender"
    trace 4 "amt: $amt"
    trace 4 "debtors: $debtors"

    trace 1 "Reason?"
    read reason

    echo "$lender $amt ${debtors[@]}" >> "$db"
    echo "$reason" >> "$db"
}

show_balance ()
{
    local names balance amt
    balance=0
    # Name being searched for.
    while read_oweage
    do
        if expr match "$1" "$lender"
        then
            names=${debtors[@]}
            balance=$(($balance + $amt - ($amt % ${#debtors[@]})))
            amt=$(($amt / ${#debtors[@]}))
        elif match_cdr "$1" ${debtors[@]}
        then
            names=$lender
            amt=$((- $amt / ${#debtors[@]}))
            balance=$(($balance + $amt))
        else
            names=""
        fi

        for name in $names
        do
            update_balances $name $amt
        done
    done < "$db"

    # Make sure the guy whose balance
    # we're getting only appears once.
    while read dude amt
    do
        if [ "$dude" = "$1" ]
        then
            balance=$(($balance - $amt))
        else
            echo $dude $amt >> "$tmp2"
        fi
    done <"$tmp1"
    mv "$tmp2" "$tmp1"
    amt=`format_amt "$balance"`
    trace 1 "Balance for $1 is $amt"
    print_balances <"$tmp1"
}

search_oweages ()
{
    local name marr sarr matchp lender amt debtors reason
    name="$1"
    marr=${@:2}
    while read_oweage
    do
        matchp=0
        if expr "$lender" : "$name"
        then
            sarr=${debtors[@]}
            match_array
            matchp=$?
        fi

        if [ $matchp -eq 1 ]
        then
            show_oweage
        fi
    done <$db
}

while [ $# -gt 0 ]
do
    flag=$1
    shift
    case "$flag" in
        '-v')
        verbose_level="$1"
        shift
        ;;

        '-d')
        db="$1"
        shift
        trace 2 "Using $db as database."

        # Make sure database exists.
        if [ ! -e "$db" ]
        then
            trace 2 "Creating database."
            touch "$db"
        fi
        ;;

        '-a')
        add_oweage "$db" ${*}
        shift $#
        ;;

        '-b')
        show_balance "$*"
        shift $#
        ;;

        '-s')
        search_oweages $*
        shift $#
        ;;

        '-r')
        regex="$1"
        shift $#
        while read_oweage
        do
            if expr "$reason" : "$regex"
            then
                show_oweage
            fi
        done <"$db"
        ;;

        *)
        show_help
        false
        ;;
    esac

    # Break if there was a problem
    test 0 -ne "$?" && break
done

rm -f "$tmp1" "$tmp2"

