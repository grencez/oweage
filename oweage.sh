#!/bin/sh

show_usage ()
{
    cat 1>&2 << "EOF"
Useage:
    oweage <option>* <action>

Options
  -v <level>
    Set verbosity level, normal crap is level 1.

Cool actions
  update-me
     Overwrite this script with the lastest stable one.
  version
     Show version information.

Repository Actions (in rough order of use)
  create <database>
     Create a repository having an empty 'oweage_database' file.
     It is not shared with anyone.
     To actually use it, see the 'use' flag.
  clone <git repository> <database>
     Clone a repository having an 'oweage_database' file (which can be empty).
     This creates a new database on your end, under the name you provided.
     To actually use it, see the 'use' flag.
  list
     List available databases.
  use <database>?
     Specify the database to use. When unspecified, show the current database.
  pull
     Call 'git pull' to update your local copy.
  log
     Call 'git log' to see recent changes.
  diff
     Show the uncommitted changes you've made.
  commit <message>
     Call 'git commit -a -m <message>' in the repository.
  push
     Call 'git push' to update the remote repository with your changes.

Database Actions (in rough order of importance)
  a <lender> <dollars>[.<cents>] <debtor>+
    Add new oweage. You will be prompted for a reason the oweage is to exist.
    Be aware that the lender should include herself in the debtor list if
    appropriate! For example, if Persephone and Hades split their $600 rent
    and Persephone pays this month, she would put:
     $ oweage a persephone 600 persephone hades
  A <lender> <dollars>[.<cents>] <debtor>+
    Add with commit and push.
  b name
    Show a person's overall balance. Positive means s/he is owed money.
  s <lender> <debtor>*
    Search oweages, all terms must match and can be sed-acceptable regular
    expressions.
  r <regex>
    Search oweages by matching a regular expression to the reason field.
EOF
    return 1
}

###### BEGIN GLOBAL VARIABLES ######

version='2016.04.01'
update_url='https://raw.githubusercontent.com/grencez/oweage/master/oweage.sh'

action=''
verbose_level=1
db=''
args=''

progdir="$HOME/.oweage"

mkdir -p "$progdir/db" || \
{
    trace -1 "Creation of $progdir/db failed!"
    exit 1
}

mkdir -p "$progdir/localrepo" || \
{
  trace -1 "Creation of $progdir/localrepo failed!"
  exit 1
}

update_cur ()
{
cat > "$progdir/cur" <<EOF
db=$db
verbose_level=$verbose_level
EOF
}

if [ ! -f "$progdir/cur" ]
then
    update_cur
fi

. "$progdir/cur"

###### END GLOBAL VARIABLES ######

set_globals ()
{
  local flag

  while true
  do
    flag="$1"
    shift
    case "$flag" in
      '-v') verbose_level="$1" ; shift ;;
      *) break ;;
    esac
  done

  case "$flag" in
    'use') action='select database' ;;
    'commit') action='commit' ; break ;;
    'a' | 'add') action='add' ;;
    'A' | 'Add') action='add_commit_push' ;;
    'b' | 'bal' | 'balance') action='balance' ;;
    's' | 'search') action='search' ;;
    'r' | 'regex') action='regex search' ;;

    'update-me' | 'version' | 'set-version' \
    | 'create' | 'clone' | 'commit' | 'push' | 'pull' | 'log' | 'diff' \
    | 'list')
    action="$flag" ;;

    *) printf 'Bad arg: %s\n' "$flag" >&2 ;;
  esac

  args=$(getopt -o '' -- "$@")

  if [ -z "$action" ]
  then
    show_usage
    echo 'Please specify an action to take!' >&2
    return 1
  fi

  return 0
}


puts ()
{
    echo "$*"
#printf '%s\n' "$*"
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

lower_case ()
{
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
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
    puts "$1" | sed -e 's/^\(.*\)\(..\)$/$\1.\2/'
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

show_oweages ()
{
    local reason lender amt debtors
    while read -r lender amt debtors
    do
        read -r reason
        show_oweage "$reason" "$lender" "$amt" "$debtors"
    done
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

add_oweage ()
{
  local db dir action lender amt debtors reason
  db=$1
  dir=$(dirname "$db")
  action="$2"
  shift 2
  lender=$(lower_case "$1")
  amt=$(unformat_amt "$2") || return 1
  shift 2
  debtors=$(lower_case "$*")

  trace -4 "db: $db"
  trace -4 "lender: $lender"
  trace -4 "amt: $amt"
  trace -4 "debtors: $debtors"

  trace 1 "Reason?"
  read reason

  puts "$lender" "$amt" "$debtors" >> "$db"
  puts "$reason" >> "$db"

  if [ 'A' = "$action" ]
  then
    cd "$dir"
    git commit -a -m "$reason"
    git push origin master
    echo 'Added. Committed. Pushed.' >&2
  else
    echo 'Added. Remember to commit and push.' >&2
  fi
}

show_balance ()
{
    local indiv_increm reducer

    indiv_increm ()
    {
        local pers lender amt amt_each debtor
        pers=$(lower_case "$1")
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
            if [ "$amt" != 0 ]
            then
                trace 1 "$name" "$(format_amt $amt)"
            fi
        done

        #trace -6 "formatter:"
        #times >&2
    }

    indiv_increm "$1" | sort | reducer | orderer "$1" | formatter

    #trace -6 "balancer:"
    #times >&2
}

search_oweages ()
{
    local lender
    lender=$(lower_case "$1")
    shift

    {
        printf '/^%s/b label0\n' "$lender"
        puts 'b next'
        puts ': label0'

        i=1
        for debtor in "$@"
        do
            debtor=$(lower_case "$debtor")
            printf '/%s/b label%d\n' "$debtor" $i
            puts 'b next'
            printf ': label%d\n' $i
            i=$(($i + 1))
        done
        puts 'p;n;p;b;: next;n'
    } \
    | sed -nf /dev/fd/0 "$db" \
    | show_oweages
}

opt_reason_regex ()
{
    local regex oweage reason
    regex=$1
    cat "$db" \
    | sed -ne "{h;n;{/${regex}/{x;p;x;p}}}" \
    | \
    while read oweage
    do
        read reason
        show_oweage "$reason" $oweage
    done
}

opt_select_database ()
{
    if [ -z "$*" ]
    then
        trace 1 "Current database is: $db"
        return 0
    fi

    db="$*"
    if [ -f "$db" ]
    then
        db=$(readlink -f "$db")
    elif [ -f "$progdir/db/$db/oweage_database" ]
    then
        db="$progdir/db/$db/oweage_database"
    else
        trace -1 "Could not find appropriate database: $db"
        return 1
    fi
    update_cur
}

opt_set_version ()
{
    local newvers
    newvers=$(date +%Y.%m.%d)
    sed -i -e "s/^version='$version'$/version='$newvers'/" "$0"
    if [ 0 -eq $? ]
    then
        trace 1 "Version updated to $newvers"
    else
        trace 1 "Version update failed, is anything corrupted?"
    fi
}

opt_create_repo ()
{
  local repo_name repo_path
  repo_name="$1"
  repo_path="localrepo/${repo_name}.git"
  if ! mkdir "$progdir/$repo_path"
  then
    trace -1 "Could not create repo"
    return 1
  fi
  cd "$progdir/$repo_path"
  git init --bare
  cd "$progdir/db"
  git clone "../$repo_path" "$repo_name"
  cd "$repo_name"
  touch oweage_database
  git add oweage_database
  git commit -a -m "initialize empty database"
  git push origin master
}

config_action ()
{
    local dir
    dir=$(dirname "$db")
    case "$action" in
        'update-me') wget -O "$0" "$update_url" ;;
        'version') trace 1 "$version" ;;
        'set-version') opt_set_version ;;
        'create') opt_create_repo "$1" ;;
        'clone') git clone "$1" "$progdir/db/$2" ;;
        'commit') cd "$dir" && git commit -a -m "$1" ;;
        'push') cd "$dir" && git push origin master ;;
        'pull') cd "$dir" && git pull origin master ;;
        'log' ) cd "$dir" && git log ;;
        'diff') cd "$dir" && git diff ;;
        'list') cd "$progdir/db" && ls ;;
        'select database') opt_select_database "$@" ;;
        *) return 0 ;;
    esac
    action=''
}

db_action ()
{
    # Make sure database exists.
    if [ ! -e "$db" ]
    then
        trace -1 "No database selected!"
        exit 1
    fi

    case "$action" in
        'add') add_oweage "$db" 'a' "$@" ;;
        'add_commit_push') add_oweage "$db" 'A' "$@" ;;
        'balance') show_balance "$@" < "$db" ;;
        'search') search_oweages "$@" ;;
        'regex search') opt_reason_regex "$1" ;;
    esac
}

set_globals "$@" || exit 1
eval set -- $args
shift
trace 3 "args are now $@"
trace 2 "Using $db as database."
trace 2 "Action: $action"


config_action "$@" && \
if [ -n "$action" ]
then
    db_action "$@"
fi

