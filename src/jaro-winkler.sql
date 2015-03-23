-- --------------------------------------------------------------------------------
-- Routine DDL
-- --------------------------------------------------------------------------------
-- from https://androidaddicted.wordpress.com/

DELIMITER $$

CREATE DEFINER=`root`@`localhost` FUNCTION `jaro_winkler_similarity`(
in1 varchar(255),
in2 varchar(255)
) RETURNS float
DETERMINISTIC
BEGIN
#finestra:= search window, curString:= scanning cursor for the original string, curSub:= scanning cursor for the compared string
declare finestra, curString, curSub, maxSub, trasposizioni, prefixlen, maxPrefix int;
declare char1, char2 char(1);
declare common1, common2, old1, old2 varchar(255);
declare trovato boolean;
declare returnValue, jaro float;
set maxPrefix=6; #from the original jaro - winkler algorithm
set common1="";
set common2="";
set finestra=(length(in1)+length(in2)-abs(length(in1)-length(in2))) DIV 4
+ ((length(in1)+length(in2)-abs(length(in1)-length(in2)))/2) mod 2;
set old1=in1;
set old2=in2;

#calculating common letters vectors
set curString=1;
while curString<=length(in1) and (curString<=(length(in2)+finestra)) do
set curSub=curstring-finestra;
if (curSub)<1 then
set curSub=1;
end if;
set maxSub=curstring+finestra;
if (maxSub)>length(in2) then
set maxSub=length(in2);
end if;
set trovato = false;
while curSub<=maxSub and trovato=false do
if substr(in1,curString,1)=substr(in2,curSub,1) then
set common1 = concat(common1,substr(in1,curString,1));
set in2 = concat(substr(in2,1,curSub-1),concat("0",substr(in2,curSub+1,length(in2)-curSub+1)));
set trovato=true;
end if;
set curSub=curSub+1;
end while;
set curString=curString+1;
end while;
#back to the original string
set in2=old2;
set curString=1;
while curString<=length(in2) and (curString<=(length(in1)+finestra)) do
set curSub=curstring-finestra;
if (curSub)<1 then
set curSub=1;
end if;
set maxSub=curstring+finestra;
if (maxSub)>length(in1) then
set maxSub=length(in1);
end if;
set trovato = false;
while curSub<=maxSub and trovato=false do
if substr(in2,curString,1)=substr(in1,curSub,1) then
set common2 = concat(common2,substr(in2,curString,1));
set in1 = concat(substr(in1,1,curSub-1),concat("0",substr(in1,curSub+1,length(in1)-curSub+1)));
set trovato=true;
end if;
set curSub=curSub+1;
end while;
set curString=curString+1;
end while;
#back to the original string
set in1=old1;

#calculating jaro metric
if length(common1)<>length(common2)
then set jaro=0;
elseif length(common1)=0 or length(common2)=0
then set jaro=0;
else
#calcolo la distanza di winkler
#passo 1: calcolo le trasposizioni
set trasposizioni=0;
set curString=1;
while curString<=length(common1) do
if(substr(common1,curString,1)<>substr(common2,curString,1)) then
set trasposizioni=trasposizioni+1;
end if;
set curString=curString+1;
end while;
set jaro=
(
length(common1)/length(in1)+
length(common2)/length(in2)+
(length(common1)-trasposizioni/2)/length(common1)
)/3;

end if; #end if for jaro metric

#calculating common prefix for winkler metric
set prefixlen=0;
while (substring(in1,prefixlen+1,1)=substring(in2,prefixlen+1,1)) and (prefixlen<6) do
set prefixlen= prefixlen+1;
end while;

#calculate jaro-winkler metric
return jaro+(prefixlen*0.1*(1-jaro));
END
