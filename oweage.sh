#!/bin/sh

#exec 3<&1
#exec 1<&-
#exec 1> /dev/null

show_help ()
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
     Search oweages, all terms must match and can be sed-acceptable
     regular expressions.
  -r  regex
     Search oweages by matching a regular expression to the reason field.
EOF
    return 1
}

verbose_level=1
db="${HOME}/.oweage_db"


puts ()
{
    echo "$*"
#    cat <<EOF
#$*
#EOF
}

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
            puts "$*"
        else
            puts "$*" >&2
        fi
    fi
}

unformat_amt ()
{
    local x y
    trace -4 "unformat_amt ($1)"

    set -- $(puts "$1" | sed -e 's/^\$\?\([0-9]*\)\.\?\([0-9]*\)$/\1 \2/')
    x=$1
    y=$2

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

    puts "$x$y"
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
    local tmp
    read -r tmp
    puts $tmp
    read -r tmp
}

# Read the oweage with the reason intact
read_full_oweage ()
{
    local tmp
    read -r tmp || return 1
    puts "$tmp"
    read -r tmp || return 1
    puts "$tmp"
}

show_oweage ()
{
    local reason lender amt
    reason=$1
    lender=$2
    amt=$(format_amt $3)
    shift 3
    trace 1 "$lender $amt $*"
    trace 1 "Reason: $reason"
}

match_cdr ()
{
    local x y
    x=$1
    shift
    for y in "$@"
    do
        test "$x" = "$y" && return 0
    done
    return 1
}

cat >/dev/null <<"EOF"
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
EOF

add_oweage ()
{
    local db lender amt debtors reason
    db=$1
    lender=$2
    amt=$(unformat_amt "$3") || return 1
    shift 3
    debtors=$*

    trace -4 "db: $db"
    trace -4 "lender: $lender"
    trace -4 "amt: $amt"
    trace -4 "debtors: $debtors"

    trace 1 "Reason?"
    read reason

    puts "$lender" "$amt" "$debtors" >> "$db"
    puts "$reason" >> "$db"
}

show_balance ()
{
    local indiv_increm reducer

    indiv_increm ()
    {
        local pers lender amt amt_each debtor
        pers=$1
        while set -- $(read_oweage) ; test -n "$*"
        do
            lender=$1 ; amt=$2 ; shift 2
            amt=$(($amt - ($amt % $#)))
            amt_each=$((- $amt / $#))
            if [ "$pers" = "$lender" ]
            then
                puts "$pers" "$amt"
                for debtor in "$@"
                do
                    puts "$debtor" "$amt_each"
                done
            elif match_cdr "$pers" "$@"
            then
                puts "$lender" "$((- $amt_each))"
                puts "$pers"        "$amt_each"
            fi
        done

        #trace -6 "indiv_increm:"
        #times >&2
    }

    reducer ()
    {
        local cur_name total name amt
        read -r cur_name total || return 1
        while read -r name amt
        do
            if [ "$name" = "$cur_name" ]
            then
                total=$(($total + $amt))
            else
                puts "$cur_name" "$total"
                cur_name="$name"
                total="$amt"
            fi
        done 
        puts "$cur_name" "$total"

        #trace -6 "reducer:"
        #times >&2
    }

    orderer ()
    {
        local name amt

        while read -r name amt
        do
            if [ "$name" = "$1" ]
            then
                puts "$name"      "$amt"   >&3
            else
                puts "$name" "$((- $amt))"
            fi
        done | sort >&3
            
        # yes hi | { tee /dev/fd/3 | sed -e 's/hi/blar/' ; } 3>&1 | sed -e 's/hi/bye/'
        #trace -6 "orderer:"
        #times >&2
    } 3>&1

    formatter ()
    {
        local name amt
        read  -r name amt || return 1
        trace 1 "Balance for $name is $(format_amt $amt)"
        while read name amt
        do
            trace 1 "$name" "$(format_amt $amt)"
        done

        #trace -6 "formatter:"
        #times >&2
    }

    indiv_increm "$1" | sort | reducer | orderer "$1" | formatter

    #trace -6 "balancer:"
    #times >&2
}

cat > /dev/null <<"EOF"
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
EOF

opt_reason_regex ()
{
    local regex oweage reason
    regex=$1
    sed -n -e "{h;n;{/${regex}/{x;p;x;p}}}" | \
    while read oweage
    do
        read reason
        show_oweage "$reason" $oweage
    done
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
        show_balance "$@" < "$db"
        shift $#
        ;;

        '-s')
        # unimplement to test
        #search_oweages "$@"
        shift $#
        ;;

        '-r')
        opt_reason_regex "$1" < "$db"
        shift $#
        ;;

        *)
        show_help
        false
        ;;
    esac

    # Break if there was a problem
    test 0 -ne "$?" && break
done

