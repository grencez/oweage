#!/bin/bash

function show_help
{
cat <<EOF
Useage:
    oweage [DATABASE] -a LENDER DOLLARS[.CENTS] DEBTOR1 [DEBTOR2 ... DEBTORN]
    oweage [DATABASE] -b NAME
    oweage [DATABASE] -s LENDER [DEBTOR1 ... DEBTORN]
    oweage [DATABASE] -r REGEX


If DATABASE is not specified, $HOME/.oweage_db will be used.

  -a  add new oweage
  -b  balance wrt the name given. Positive numbers indicate s/he is owed money
  -s  search oweages, all terms must match
  -r  match a oweage reason with a regular expression
EOF
}

args=($@)
i=0
tmp1=`tempfile`
tmp2=`tempfile`

if [[ "${args[$i]}" =~ ^- ]]
then
    #echo match
    db="${HOME}/.oweage_db"
else
    #echo no match
    db=$1
    let ++i
fi

# Make sure database exists.
if [ ! -f $db ]
then
    touch $db
fi

## used by follewing functions
amt=0

function unformat_amt
{
    amt=${amt//\$/}

    if [[ $amt =~ \..$ ]]
    then
        amt=${amt//\./}0
    elif [[ $amt =~ \...$ ]]
    then
        amt=${amt//\./}
    elif [[ $amt =~ \. ]]
    then
        echo "AMOUNT ($amt) DOESN'T MAKE CENTS"
        exit 1
    else
        amt="${amt}00"
    fi
}

function format_amt
{
    cut_index=${#amt}
    if [ $cut_index -eq 1 ]
    then
        amt="\$0.0${amt}"
    elif [ $cut_index -eq 2 ]
    then
        amt="\$0.${amt}"
    else
        cut_index=$(($cut_index - 2))
        amt="\$${amt:0:$cut_index}.${amt:$cut_index}"
    fi
}

function read_oweage
{
    if ! read -a token
    then
        return 1
    fi
    lender=${token[0]}
    amt=${token[1]}
    debtors=(${token[@]:2})
    read
    reason=$REPLY
}

function show_oweage
{
    format_amt
    echo $lender $amt ${debtors[@]}
    echo "Reason:" $reason
}

function match_lender
{
    if [ $lender = $name ]
    then
        return 0
    else
        return 1
    fi
}

function match_debtor
{
    for str in ${debtors[@]}
    do
        if [ $str = $name ]
        then
            return 0
        fi
    done
    return 1
}

function update_balances
{
    found=0
    while read x y
    do
        if [ $x = $name ]
        then
            y=$(($y + $amt))
            found=1
        fi
        echo $x $y >>$tmp2
    done <$tmp1

    if [ 0 -eq $found ]
    then
        echo $name $amt >>$tmp2
    fi
    mv $tmp2 $tmp1
}

function print_balances
{
    while read x y
    do
        amt=$y
        format_amt
        echo $x $amt
    done
}

function match_array
{
    # sarr - array searching
    # marr - array to match
    for x in ${marr[@]}
    do
        matchp=0
        for y in ${sarr[@]}
        do
            if [ $x = $y ]
            then
                matchp=1
            fi
        done
        if [ $matchp == 0 ]
        then
            return 1
        fi
    done
    return 0
}

flag=${args[$i]}
let ++i

case "$flag" in
    '-a')
    lender=${args[$i]}
    let ++i
    amt=${args[$i]}
    unformat_amt
    let ++i
    debtors=${args[@]:$i}

    echo -n "Reason? "
    read reason

    echo $lender $amt ${debtors[@]} >> $db
    echo $reason >> $db

    #echo "DEBUG:"
    #echo "lender:" $lender
    #echo "amt:" $amt
    #format_amt
    #echo "formatted:" $amt
    #echo "debtors:" $debtors
    #echo "Reason:" $reason
    ;;

    '-b')
    balance=0
    # Name being searched for.
    cool_guy=${args[$i]}
    let ++i
    while read_oweage
    do
        name=$cool_guy
        names=
        if match_lender
        then
            names=${debtors[@]}
            balance=$(($balance + $amt))
            amt=$(($amt / ${#debtors[@]}))
            #echo "lender $amt $balance"
        elif match_debtor
        then
            names=$lender
            #echo -n "debtor $amt"
            amt=$((- $amt / ${#debtors[@]}))
            balance=$(($balance + $amt))
            #echo " $balance"
        fi
        
        for name in $names
        do
            update_balances
        done
    done < $db

    # Make sure the guy whose balance
    # we're getting only appears once.
    while read dude amt
    do
        if [ $dude = $cool_guy ]
        then
            balance=$(($balance - $amt))
        else
            echo $dude $amt >> $tmp2
        fi
    done <$tmp1
    mv $tmp2 $tmp1
    amt=$balance
    format_amt
    echo "Balance for" $cool_guy "is" $amt
    print_balances <$tmp1
    ;;

    '-s')
    name=${args[$i]}
    let ++i
    marr=${args[@]:$i}
    while read_oweage
    do
        matchp=0
        if [ $lender = $name ]
        then
            sarr=${debtors[@]}
            if match_array
            then
                matchp=1
            fi
        fi

        if [ $matchp == 1 ]
        then
            show_oweage
        fi
    done <$db
    ;;

    '-r')
    regex=${args[$i]}
    while read_oweage
    do
        if [[ $reason =~ $regex ]]
        then
            show_oweage
        fi
    done <$db
    ;;

    *)
    show_help
    ;;
esac

rm -f $tmp1 $tmp2

