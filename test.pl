]# cat EventDrainSuccessCount.monitor 
#!/usr/bin/perl
#このmonitorはjmxquery.jarを利用してmbeansをチェックします。その為、jmxquery.jarの仕様に則った形でコマンドを生成してチェックします。
use strict;
#幾つかの警告メッセージを出してくれる
use warnings;
use File::Copy 'move';
#コマンドラインオプションを処理するには Getopt::Long モジュールの GetOptions 関数を宣言する
#posix_defaultを書いておくとauto_abbrev とか permuteなどがオフになる。 ignore_case だけは posix_default を指定してもオフにならないので、これは個別にオフにする必要がある
#オプション名に short option (1文字のオプション)を使用するとき、そのオプションについて大文字小文字の区別を無視する。デフォルトで有効
#--option=value といった、形式の指定がデフォルトでは無効のため有効にするためにはgnu_compat を指定
use Getopt::Long qw(:config posix_default no_ignore_case gnu_compat);
#変数宣言
#$は変数 @は配列にいれる
my $java = "/usr/local/java/bin/java";
#my $jar = "/usr/local/mon/mon.d/jmxquery.jar";
my $jar = "/home/share/mishina_kohei/jmxquery.jar";
my $tmpdir = "/var/tmp/";
my @mbeans_list;
my @attributes_list;
my $port;
my $threshold = 1;
my $timeout = 4;
my $HELP;
 
GetOptions(
    "p=i" => \$port,
    "a=s{1,}" => \@attributes_list,
    "b=s{1,}" => \@mbeans_list,
    'help' => \$HELP
) || die("GetOptions failed") ;
#オプションがまちがっていればGetOptions failedを出力する
#helpがオプションに指定されていたらthis monitor usage : { monitor -b [jmx mbeans] -a [jmx attributes] -p [port] -t [threshold] [host_ip]}を表示する
if ( $HELP ) {
    die "this monitor usage : { monitor -b [jmx mbeans] -a [jmx attributes] -t [threshold] -p [port] [host_ipi}"
}
#オプションに設定された情報を利用して指定されたmbeansの値を取得、チェックします。
#但し二つの値を取得してその割合を計算する場合を考慮して、ここではチェックしたステータスを戻り値に入れるだけでmonitor全体の判定はしません。
#閾値を中で二つ作っているのは、check_jmxを実行する際に-w(warnigs)と-c(critical)用の値をセットする必要があり
#閾値判定処理は-wに$thresholdを使用して、-cはそれより値が大きければなんでもいいので
#2倍にしたあと+1しています。
#サブルーチンの宣言
sub pending_status_get{
    my $host = $_[0];
    my $mbeans = $_[1];
    my $attributes = $_[2];
    my $threshold = $_[3];
    my $timeout = $_[4];
    my $threshold2 = ($threshold * 2) + 1;
    my $status_result;
    my $retval = $?;
    eval {
        $SIG{ALRM} = sub { die $status_result = "Status=TimeOutError";};
        alarm $timeout;
        my $cmd = "$java -cp $jar org.nagios.JMXQuery -U service:jmx:rmi:///jndi/rmi://$host:$port/jmxrmi -O $mbeans -A $attributes -w $threshold -c $threshold2 ";
        $status_result = qx{$cmd} or die ;
        $retval = $?;
        if ( $retval != 0 ){
            alarm 0;
        }
        alarm 0;
    };if ($@) {
          $retval = 1;
      }
    chomp($status_result);
    my @host_status_list = ($host,$mbeans,$status_result,$retval);
    return @host_status_list;
}
my $ng_flag = 0;
my @host_list = @ARGV;
my $host_count = @host_list;
if ($host_count == 0){
    exit 0;
}
#繰り返し処理を実行する
foreach my $host (@host_list){
    foreach my $mbeans (@mbeans_list){
        foreach my $attributes (@attributes_list){
            #サブルーチンで実行された戻り値が@host_status_listにはいる
            my @host_status_list = pending_status_get($host,$mbeans,$attributes,$threshold,$timeout);
            my $file ="$tmpdir$host_status_list[0]-$host_status_list[1].txt";
            my $file_bk ="$tmpdir$host_status_list[0]-$host_status_list[1]_bk.txt";
            #サブルーチンで実行されたコマンドの結果が閾値を超えていたらif文の中を実行
	    if ( $host_status_list[3] != 0){
		#指定した場所に$fileが存在していたらif文の中を実行
                if (-e $file){
                    #前回の時に作成されたファイルの名前を変更して今回実行されたコマンドの結果を新しいファイルに出力する
                    move($file, $file_bk) or die("error :$!");
                    open(DATAFILE, "> $file") or die("error :$!");
                    print DATAFILE "$host_status_list[2]";
                    #２つの変数の中に前回の結果と今回の結果を代入する
                    my $succes_count = qx`cat $file`;
                    my $succes_count_bk = qx`cat $file_bk`;
                    #２つのファイルの中身が一緒だったら、実行結果とIPを標準出力する。$ng_flag=1をたてる
		    if ("$succes_count" eq "$succes_count_bk" ){
		        print "$host_status_list[0] => EventDrainSuccessCount not increase for 12 hour!! value : $host_status_list[2]\n";
                        $ng_flag = 1;
                    }
                #$fileが指定の場所に存在しなければ、ファイルを作成してコマンドの実行結果$fileに書き込む
                open(DATAFILE, "> $file") or die("error :$!");
                print DATAFILE "$host_status_list[2]";
                }
            }
	close(DATAFILE);
        }
    }
}
#NGフラグを確認して、立っていれば戻り値を１で終了
##NGフラグがたっていればエラー出力をしてexit1を返す
if ( $ng_flag == 1){
    print "JMX Params Status is NG!!\n";
    exit 1;
}
    #NGフラグがひとつもなければ正常であるという出力をする
    print " JMX Params Status is ALL OK!!\n";
    exit 0;
