# Documentation

Refer to SMS documentation at <https://sat-modulo-symmetries.readthedocs.io/> for installation instructions.
Additionally build `march_cu` in the `march_cu` subdirectory and put it on `$PATH`.

## command lines generating default cubes with default cubers:
```bash
cubers: `sms-def`, `sms-la-all`, `sms-la-edge` and `march`;
problem_name: `kochen-specker`, `traingle-free`, and `murty-simon`;
prerun: `600`
bash ./cube-tool.sh --$problem_name -v $number_of_vertex --prerun-time $prerun -b $cuber --reuse-learned-clauses
```

## command lines generating cubes with march parameters:
```
cubers: `sms-def`, `sms-la-all`, `sms-la-edge` and `march`;
problem_name: `kochen-spcher`, `traingle-free`, and `murty-simon`;
prerun: `600`
march_function (index of the scoring functions): 1 kochen specker, 12 for traingle free and murty simon problems
the paramters bin, dec, min, max of march can be set accordingly
bash ./cube-tool.sh --$problem_name -v $number_of_vertex --prerun-time $prerun -b $cuber --reuse-learned-clauses --py /home1/hxia/software/python_auto_cubing/bin/python --cube-args -bin $march_bin_value -dec $march_dec_value -min $march_min_value -max $march_max_value -f $march_function --
```

## solving the cubes of best configurations
best parameters for KS:
--cutoff 199693 --frequency 282 --cadical-config block=true bump=true forcephase=true stabilize=true blockmaxclslim=4674994 blockminclslim=991 bumpreasondepth=2 stabilizefactor=57471588 stabilizemaxint=99796564 stabilizeonly=true

best parameters for MS:
--cutoff 54085 --frequency 22 --cadical-config block=true bump=true forcephase=false stabilize=false blockmaxclslim=7638137 blockminclslim=683 bumpreasondepth=1

best parameters for TF:
--cutoff 699 --frequency 63 --cadical-config block=true bump=true forcephase=true stabilize=true blockmaxclslim=4904 blockminclslim=924 bumpreasondepth=3 stabilizefactor=72633272 stabilizemaxint=19458 stabilizeonly=false
