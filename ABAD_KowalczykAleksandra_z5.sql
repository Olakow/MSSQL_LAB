-- ALEKSANDRA KOWALCZYK
--307414


/* usuwanie kolumny z tabeli
** Procedura BD z 3 par
** nazwa bazy, nazwa tabeli, nazwa kol
**
** 1. Sprawdzamy czy kolumna istnieje (zapytanie z syscolumns po�aczone z sysobjects po ID)
** 1.1. Jak istnieje sprawdzamy czy s� pewne ograniczenia (np DEFAULT by� za�o�ony)
** 1.2 Jak TAK - usuwamy ograniczenia
** 1.3. Usuwamy kolumne
*/


use DB_STAT
go

/* przyk�ad - tworz� tabel� z DEFAULT - to tworzy automatycznie ograniczenie na kolumnie */
CREATE TABLE dbo.test_dr
(	[id] nchar(6) not null
,	nazwa_wlasna nchar(100) not null
,	czy_wazny bit NOT NULL default 0 /* to powoduje powstanie constrain 
									** system nada unialn� nazw� */
)
go

INSERT INTO test_dr ([id], nazwa_wlasna) VALUES (N'ala',N'wyspa' )
INSERT INTO test_dr ([id], nazwa_wlasna, czy_wazny) VALUES (N'kot', N'plaza', 1)

SELECT * FROM test_dr

-- chcemy usun�� kolumn�
ALTER TABLE test_dr drop column czy_wazny

-- wy�wietla nam si� b��d
/*
Msg 5074, Level 16, State 1, Line 31
The object 'DF__test_dr__czy_waz__619B8048' is dependent on column 'czy_wazny'.
Msg 4922, Level 16, State 9, Line 31
ALTER TABLE DROP COLUMN czy_wazny failed because one or more objects access this column.

*/
-- nie mo�emy usun�� tej kolumny, poniewa� jest na ni� za�o�one pewne ograniczenie
-- dlatego najpierw musimy usun�� ograniczenie, a dopiero potem mo�emy usun�� kolumn�


-- tworz� do tego procedur�:

use DB_STAT
go

CREATE PROCEDURE procedure_to_drop_col
@db nvarchar(256), @table_name nvarchar(256) , @col_name nvarchar(256)
as
BEGIN

DECLARE @name NVARCHAR(MAX)

-- sprawdzam czy kolumna istnieje 
IF EXISTS (select * from sys.columns where name = @col_name AND object_id=object_id(@table_name) ) 
BEGIN

-- jesli istnieje to tworz� zmienn� 'name' do kt�rej b�d� chciala przypisac nazwe ograniczenia
     select @name=( select d.name
     from 
         sys.tables t
         join sys.default_constraints d on d.parent_object_id = t.object_id
         join sys.columns c on c.object_id = t.object_id
                               and c.column_id = d.parent_column_id
     where 
         t.name = @table_name
         and c.name = @col_name) 

-- sprawdzam czy istnieje ograniczenie
	IF OBJECT_ID(@name, 'D') IS not  NULL
BEGIN
-- jesli istnieje ograniczenie to tworz� komend� do usuniecia ograniczenia
	DECLARE @Command NVARCHAR(MAX)
	select @Command ='Alter Table ' + @table_name + ' Drop Constraint ' + @name  
	print(@Command)
	-- uruchamiam
	exec sp_executesql @Command
END

-- tworz� komend� do usuniecia kolumny
DECLARE @Command2 NVARCHAR(MAX)
select @Command2 ='Alter Table ' + @table_name + ' Drop Column ' + @col_name
exec sp_executesql @Command2

END

end
go



-- wynik dzialania

SELECT * FROM test_dr

/*
ala   	wyspa   	0
kot   	plaza   	1
*/

-- sprawdzam czy jak usun� kolumn� bez ograniczenia to moje polecenie zadzia�a poprawnie:
EXEC procedure_to_drop_col N'DB_STAT' , N'test_dr', N'nazwa_wlasna'

/*
ala   	0
kot   	1
*/
-- widzimy, �e dzia�a poprawnie

-- sprawdzam czy moje polecenie poprawnie usunie kolumne Z OGRANICZENIEM
EXEC procedure_to_drop_col N'DB_STAT' , N'test_dr', N'czy_wazny'

/*
ala   
kot   
*/
-- usuwa poprawnie


-- sprawdzam czy moje polecenie jest odporne, gdy podam nazw� kolumny kt�ra nie istnieje
EXEC procedure_to_drop_col N'DB_STAT' , N'test_dr', N'czy_wazny'
-- tak, przechodzimy przez procedur�, nie wykonuj� si� �adne dzia�ania, ale nie wyrzuca przy tym b��d�w
