#!/bin/bash

#exec 3<&1
#exec 1<&-
#exec 1> /dev/null

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

verbose_level=1
db="${HOME}/.oweage_db"

trace ()
{
    local lvl plusp
    if [ $1 -gt 0 ]
    then
        plusp=1
        lvl=$1
    else
        plusp=0
        lvl=$((- $1))
    fi
    shift

    if [ $lvl -le $verbose_level ]
    then
        if [ $plusp -eq 1 ]
        then
            echo "$*"
        else
            echo "$*" >&2
        fi
    fi
}

unformat_amt ()
{
    local amt x y
    trace -4 "unformat_amt ($1)"

    amt=(`echo "$1" | sed -e 's/^\$\?\([0-9]*\)\.\?\([0-9]*\)$/\1 \2/'`)
    x=${amt[0]}
    y=${amt[1]}

    trace -4 "$x $y"

    # Sanity checking
    if [ "${#y}" -gt 2 ]
    then
        trace -1 "You specified too many pennies!"
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
    for str in "${@:2}"
    do
        test "$str" = "$1" && return 0
    done
    return 1
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
            if [ "$x" = "$y" ]
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
    debtors=("${@:4}")

    trace -4 "db: $db"
    trace -4 "lender: $lender"
    trace -4 "amt: $amt"
    trace -4 "debtors: $debtors"

    trace 1 "Reason?"
    read reason

    echo "$lender $amt ${debtors[@]}" >> "$db"
    echo "$reason" >> "$db"
}

show_balance ()
{
    local indiv_increm reducer

    indiv_increm ()
    {
        local lender debtors amt amt_each reason name
        while read_oweage
        do
            amt=$(($amt - ($amt % ${#debtors[@]})))
            amt_each=$((- $amt / ${#debtors[@]}))
            if [ "$1" = "$lender" ]
            then
                echo "$1 $amt"
                for name in "${debtors[@]}"
                do
                    echo "$name $amt_each"
                done
            elif match_cdr "$1" "${debtors[@]}"
            then
                echo "$lender $((- $amt_each))"
                echo "$1 $amt_each"
            fi
        done
    }

    reducer ()
    {
        local cur_name total name amt
        read cur_name total || return 1
        while read name amt
        do
            if [ "$name" = "$cur_name" ]
            then
                total=$(($total + $amt))
            else
                echo "$cur_name $total"
                cur_name="$name"
                total="$amt"
            fi
        done 
        echo "$cur_name $total"
    }

    orderer ()
    {
        local name amt

        while read name amt
        do
            if [ "$name" = "$1" ]
            then
                echo "$name"  "$amt" >&3
            else
                echo "$name" "$((- $amt))"
            fi
        done | sort >&3
            
        # yes hi | { tee /dev/fd/3 | sed -e 's/hi/blar/' ; } 3>&1 | sed -e 's/hi/bye/'
    } 3>&1

    formatter ()
    {
        local name amt
        read name amt || return 1
        trace 1 "Balance for $name is $(format_amt $amt)"
        while read name amt
        do
            trace 1 "$name $(format_amt $amt)"
        done
    }

    < "$db" indiv_increm "$1" | sort | reducer | orderer "$1" | formatter
}

search_oweages ()
{
    local name marr sarr matchp lender amt debtors reason
    name="$1"
    marr=${@:2}
    while read_oweage
    do
        matchp=0
        if [ "$lender" = "$name" ]
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

if [ $# -eq 0 ]
then
    show_help
    exit 1
fi

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
        add_oweage "$db" "$@"
        shift $#
        ;;

        '-b')
        show_balance "$@"
        shift $#
        ;;

        '-s')
        search_oweages "$@"
        shift $#
        ;;

        '-r')
        regex="$1"
        shift $#
        while read_oweage
        do
            if expr "$reason" : "$regex" >/dev/null
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

