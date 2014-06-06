#!usr/bin/perl

use strict;

sub resolve_input_files (@);
sub fetch_file_content ($);
sub replace_latex (@);
sub set_paragraph (@);

my $from_file = shift();
my $to_folder = shift();
$to_folder =~ s/\///g;

my @fromfile_content = resolve_input_files( fetch_file_content( $from_file ) );
my @html_content = replace_latex( @fromfile_content);
my %pages = set_paragraph( @html_content );

#cleanup before
system "rm $to_folder/*.html";

my @index = ();
#output HTML-Pages
foreach (sort {int($a) <=> int($b)} keys(%pages)) {
	my $page = $_;
	my $to_file = lc($_).".html";
	$to_file =~ s/ä/ae/g;
	$to_file =~ s/ö/oe/g;
	$to_file =~ s/ü/ue/g;
	$to_file =~ s/ß/ss/g;
	$page =~ s/\d*_//;
	push @index, "<a href=\"$to_file\">$page</a><br>";	#build index
	open(OUTPUT, ">$to_folder/$to_file") || die "could not open $to_folder/$to_file\n";
	print OUTPUT join("\n",@{$pages{$_}});
	close(OUTPUT);
}
#create Index
open(INDEX, ">$to_folder/index.html") || die "could not open $to_folder/index.html";
print INDEX join("\n",@index);
close(INDEX);

#resolve included input-files (push all the text into a single list)
sub resolve_input_files (@) {
	my @text = @_;
	my @output = ();
	foreach  my $line(@text) {
		while (($line=~/\\input\{.*\}/)||($line=~/\\include\{.*\}/)) {
			if ($line !~ /^\s*%.*/){	#ignore comments
				my $linecontent_before = $`;
				my $linecontent_after = $';
				my $file = $&;
				$line =~ s/$file//;
				$file =~ s/\\input\{//;
				$file =~ s/\\include\{//;
				$file =~ s/\}//;
				print "INPUT: $file (";
				#get content of included files
				my @inputfile_content = fetch_file_content("$file.tex");
				print @inputfile_content." lines)\n";
				#replace \input in included files ...
				@inputfile_content = resolve_input_files(@inputfile_content);
				if ($linecontent_before ne "") {
					push @output, $linecontent_before;
				}
				foreach (@inputfile_content) { push @output, $_; }
				if ($linecontent_after ne "") {
					$line = $linecontent_after;
				}
			} else {
				last;
			}
		}
		if ($line !~ /^\s*%.*/){	#ignore comments
			$line =~ s/%.*$//;	#remove comments
			push @output, $line;
		}
	}
	return @output;
}
#get content of file
sub fetch_file_content ($) {
	my $filename = shift();
	open( INPUT, "<$filename" ) || die "could not open $filename\n";
	my @content = <INPUT>;
	chomp(@content);
	close( INPUT );
	return @content;
}
#replace latex-commands
sub replace_latex (@) {
	my @text = @_;
	my @output = ();
	my %user_commands = find_newcommands( @text );			#user-commands without params
	my %param_commands = find_paramcommands( @text );	#user-commands with params
	#first: resolve included files
	@text = resolve_input_files (@text);
	#fetch title-page
	print "save titlepage ...\n";
	my $start_title_page = 0;
	my @titlepage = ();
	foreach my $pos(1..@text) {
		my $line = $text[$pos - 1];
		if ($line =~ /\\begin\{titlepage\}/) {$start_title_page = 1; }
		if ($start_title_page) {
			push @titlepage, $line;
			$text[$pos - 1] = "";
		}
		if ($line =~ /\\end\{titlepage\}/) {$start_title_page = 0; }
	}
	#convert latex
	print "convert latex ...\n";
	my $content_started = 0;
	my $textline_before = 0;
	foreach my $line(@text) {
		#remove \newcommand
		$line =~ s/\\newcommand\{.*\}\{.*\}//g;
		$line =~ s/\\newcommand\{.*\}\[\d*\]\{.*\}//g;
		$line =~ s/\\tableofcontents//g;
		if ($line  !~ /^\s*%.*/) {	#ignore comments
			foreach my $command (sort(keys(%user_commands))) {
				#replace user-defined commands with their corresponding values
				my $find_command = $command;
				$find_command =~ s/^\d//;
				$line =~ s/$find_command/$user_commands{$command}/g;
			}
			foreach my $command (sort(keys(%param_commands))) {
				#replace user-defined param-commands with their corresponding values
				while ($line =~ /$command/) {
					my $line_before = $`;
					$line =~ s/.*$command\{//; #prepare for first parameter
					my $replaced = "";
					#fetch following parameters
					my %command_params = %{ $param_commands{$command} };
					for (1..$command_params{"COUNT"}){
						my $param = $line;
						$param =~ s/\}.*//; #fetch parameter
						$line =~ s/.*\{//; #prepare for next parameter
						$replaced .= $command_params{"BEFORE$_"}.$param; #concatenate new string
					}
					$line =~ s/.*\}//;#remove last parameter
					$replaced .= $command_params{"AFTER"};
					print "$command => $replaced\n";
					$line = $line_before.$replaced.$line;	#insert new string where old one has been before
				}
			}
			if ($line =~ /\\begin\{document\}/) {
				#start of document-boundaries
				$line =~ s/\\begin\{document\}//;
				$content_started = 1;
			}
			if ($line =~ /\\end\{document\}/) {
				#end of document-boundaries
				$line =~ s/\\end\{document\}//;
				$content_started = 0;
			}
			if ($content_started){
				#convert text-structure to html
				$line = replace_command($line,"chapter","h1");
				$line = replace_command($line,"section","h2",,"\n");
				$line = replace_command($line,"subsection","h3",,"\n");
				$line = replace_command($line,"emph","i");
				$line = replace_command($line,"textsc","span style=\"font-variant:small-caps\"","span");
				#convert symbols
				$line = replace_symbol($line,"--","&ndash;");
				$line = replace_symbol($line,"\\\\ldots","&hellip;");
				$line = replace_symbol($line,"\"'","&rdquo;");
				$line = replace_symbol($line,"\"`","&bdquo;");
				$line = replace_symbol($line,"\\\{","");
				$line = replace_symbol($line,"\\\}","");
				$line = replace_symbol($line,"\\\\ "," ");
				#add line to output
				$line =~ s/%.*$//;		#remove comments
				$line =~ s/\\\s*$//;	#remove trailing \
				$line =~ s/\r//;	#remove carriage return
				if ($textline_before || $line !~ /^$/) {
					push @output, $line;
				}
				#reduce empty lines
				if ($line !~ /^\s*$/) {
					$textline_before = 1;
				} else {
					$textline_before  = 0;
				}
			}
		}
	}
	return @output;
}
#replace latex-command with html-tag
sub replace_command ($$$$) {
	my ($line,$latex,$html, $html_end, $insert_after) = @_;
	if (($html_end eq undef) || ($html_end =~ /^\s*$/)) { $html_end = $html; }
	#~ if ($insert_after eq undef) {$insert_after = ""};
	while ($line =~ /\\$latex\{.*\}/) {
			my $linecontent_before = $`;
			my $linecontent_after = $';
			my $latexname = $&;
			$latexname =~ s/\\$latex\{/<$html>/;
			$latexname =~ s/\}/<\/$html_end>/;
			$line = $linecontent_before.$latexname.$insert_after.$linecontent_after;
			print uc($latex).": $latexname\n";
	}
	return $line;
}
#replace latex-symbols with html-symbols
sub replace_symbol ($$$) {
	my ($line,$latex,$html) = @_;
	$line =~ s/$latex/$html/g ;
	return $line;
}
#find user-defined latex-commands
sub find_newcommands(@) {
	my @text = @_;
	my %custom_commands = ();
	foreach my $line(@text) {
		while ($line =~ /\\newcommand\{.*\}\{.*\}/) {
			my $linecontent_before = $`;
			my $linecontent_after = $';
			my $latexname = $&;
			if ($line !~ /^\s*%.*/) {	#ignore comments
				my $custom_command = $latexname;
				$custom_command =~ s/\\newcommand\{//;
				$custom_command =~ s/\}\{.*\}//;
				$custom_command =~ s/\\/\\\\/g;
				my $replace_with = $latexname;
				$replace_with =~ s/.*\}\{//;
				$replace_with =~ s/\}//;
				if ($replace_with =~ /^\{/){
					$replace_with =~ s/^\{//;
					$replace_with =~ s/\}$//;
				}
				$custom_commands{"1".$custom_command." "} = $replace_with;
				$custom_commands{"2".$custom_command} = $replace_with;
				print "$custom_command => $replace_with\n";
				$line = $linecontent_before.$linecontent_after;
			}
		}
	}
	return %custom_commands;
}
#find user-defined parameterized latex-commands
sub find_paramcommands (@) {
	my @text = @_;
	my %param_commands = ();
	foreach my $line(@text) {
		while ($line =~ /\\newcommand\{.*\}\[\d*\]\{.*\}/) {
			my $linecontent_before = $`;
			my $linecontent_after = $';
			my $latexname = $&;
			if ($line !~ /^\s*%.*/) {	#ignore comments
				my $custom_command = $latexname;
				$custom_command =~ s/\\newcommand\{//;
				$custom_command =~ s/\}\[\d*\]\{.*\}//;
				$custom_command =~ s/\\/\\\\/g;
				my $param_count = $latexname;
				$param_count =~ s/.*\[//;
				$param_count =~ s/\].*//;
				my $replace_with = $latexname;
				$replace_with =~ s/\\newcommand\{.*\}\[\d*\]\{//;
				$replace_with =~ s/\}//;

				#save structure
				my %command_parts = ();
				$command_parts{"NAME"} = $custom_command;
				$command_parts{"COUNT"} = $param_count;
				for (1..$param_count) {
					my $before = $replace_with;
					$before =~ s/\#$_.*//;
					$command_parts{"BEFORE$_"} = $before;
					$replace_with =~ s/.*\#$_//;
				}
				$command_parts{"AFTER"} = $replace_with;
				print "$latexname: ".join(",",%command_parts)."\n";

				$param_commands{$custom_command} = \%command_parts;

				$line = $linecontent_before.$linecontent_after;
			}
		}
	}
	return %param_commands;
}
#convert paragraphs
sub set_paragraph (@) {
	my @text = @_;
	my $headline_before = 0;
	my %pages = ();
	my $inside_paragraph = 0;
	my $pagenr = 0;
	my $current_page ;
	print "\n====================\n";
	print "searching paragraphs\n";
	my $pagename = "";
	foreach my $line(@text) {
		if (!$headline_before) {
			if ($line =~ /<h\d>/) {
				if ($inside_paragraph) {
					#end of paragraph found
					push @$current_page,"</p>";
					$inside_paragraph = 0;
				}
				#start of page found
				$pagename = $line;
				$pagename =~ s/^.*<h\d>//;
				$pagename =~ s/<\/h\d>.*$//;
				my @newpage = ();
				$current_page = \@newpage;
				$pages{++$pagenr."_".$pagename} = $current_page;
			} else {
				if ($inside_paragraph && $line =~ /^\s*$/) {
					#end of paragraph found
					push @$current_page, "</p>";
					$inside_paragraph = 0;
				} elsif (!$inside_paragraph && $line !~ /^\s*$/) {
					#we are not inside a paragraph and this is not an empty line and there is no head-line right before
					#=> start of paragraph found
					print "<p> found ($pagename): ". substr($line,0,40)."\n";
					$line = "<p>".$line;
					$inside_paragraph = 1;
				}
			}
		} else {
			if ($line !~ /<h\d>/ && $line !~ /^\s*$/ && !$inside_paragraph) {
				#we are not inside a paragraph, this is not an empty line and our line does not contain a head-line
				#but there is a headline right before
				#=> start of paragraph found
				print "<p> found ($pagename): ". substr($line,0,40)."\n";
				$line = "<p>".$line;
				$inside_paragraph = 1;
			}
		}
		if ($line =~ /<h\d>/) {
			$headline_before = 1;
		} else {
			$headline_before = 0;
		}
		push @$current_page, $line;
	}
	return %pages;
}
