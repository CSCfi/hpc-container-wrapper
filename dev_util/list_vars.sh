grep -o "CW_[^ ,:/\[-]*[\" ]" -r | cut -d ":" -f2 | sed 's/"//g' | sed 's/=//g' | sed 's/\s*//g' | sort  | uniq
