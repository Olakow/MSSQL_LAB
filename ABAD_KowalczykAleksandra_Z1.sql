-- Aleksandra Kowalczyk 307414


-- ZADANIE 1  - POLECENIE:

/* 

Zadanie dla studentów:

1. Stworzyć tabelę do przechowywania WSZYSTKICH kluczy obcych w danej bazie (połączona relacją z DB_STAT 
- dzięki relacji wiemy jaka to baza)
2. Stworzyc procedure do zapamietania wszystkich luczy obcych z wykorzystaniem tabel - patrz pkt 1
3. Procedura do kasowania kluczy obcych - najpierw uruchamia procedure z punktu 2 a następnie kasuje klucze
4. Napisanie procedury do odtworzenia kluczy obcych ostatnio zapisanych
- szukanie MAX z DB_STAT gdzie był backup kluczy z danej bazy ifaktycznie są tam rekordy

*/


-- KOD:


-- tworzymy bazę DB_STAT jeśli nie istenieje
IF NOT EXISTS (SELECT d.name 
					FROM sys.databases d 
					WHERE	(d.database_id > 4) -- systemowe mają ID poniżej 5
					AND		(d.[name] = N'DB_STAT')
)
BEGIN
	CREATE DATABASE DB_STAT
END
GO

USE DB_STAT
GO

-- tworzymy tabelę DB_STAT gdzie będziemy przechowywać informacje o wykonanych procedurach

IF NOT EXISTS 
(	SELECT 1
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = N'DB_STAT')
		AND		(OBJECTPROPERTY(o.[ID],N'IsUserTable')=1)
)
BEGIN

	CREATE TABLE dbo.DB_STAT
	(	stat_id		int				NOT NULL IDENTITY /* samonumerująca kolumna */
			CONSTRAINT PK_DB_STAT PRIMARY KEY
	,	[db_nam]	nvarchar(20)	NOT NULL
	,	[comment]	nvarchar(20)	NOT NULL
	,	[when]		datetime		NOT NULL DEFAULT GETDATE()
	,	[usr_nam]	nvarchar(100)	NOT NULL DEFAULT USER_NAME()
	,	[host]		nvarchar(100)	NOT NULL DEFAULT HOST_NAME()
	)
END
GO

USE DB_STAT
GO

-- tworzymy tabele DB_RCOUNT w której będziemy przechowywać informacje o liczbie wierszy w danych kolumnach bazy

IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = N'DB_RCOUNT')
		AND		(OBJECTPROPERTY(o.[ID], N'IsUserTable')=1)
)
BEGIN
	CREATE TABLE dbo.DB_RCOUNT
	(	stat_id		int				NOT NULL CONSTRAINT FK_DB_STAT__RCOUNT FOREIGN KEY
											REFERENCES dbo.DB_STAT(stat_id)
	,	[table]		nvarchar(100)	NOT NULL
	,	[RCOUNT]	int				NOT NULL DEFAULT 0
	,	[RDT]		datetime		NOT NULL DEFAULT GETDATE()
	)
END
GO

USE DB_STAT
GO

/* stworzyć tabelę do przechowywania kluczy obcych na bazie */
IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = N'DB_FK')
		AND		(OBJECTPROPERTY(o.[ID], N'IsUserTable')=1)
)
BEGIN
	CREATE TABLE dbo.DB_FK
	(	stat_id					int		NOT NULL --id to przydzielony numer procedury
			CONSTRAINT FK_DB_FK__RCOUNT FOREIGN KEY REFERENCES dbo.DB_STAT(stat_id)				
	,	[constraint_name]			nvarchar(100)	NOT NULL --nazwa klucza obcego											
	,	[delete_table_name]			nvarchar(100)	NOT NULL --nazwa usuwanej tabeli
	,	[delete_table_column_name]		nvarchar(100)	NOT NULL --nazwa kolumny w usuwanej tabeli
	,	[master_table_name]			nvarchar(100)	NOT NULL --nazwa głównej tabeli 
	,	[master_table_column_name]		nvarchar(100)	NOT NULL --nazwa kolumny w głównej tabeli
	)
END
GO

USE DB_STAT 
GO

/* stworzyć procedurę do przechowywania liczby wierszy w wybranej bazie */
IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = 'DB_TC_STORE')
		AND		(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.DB_TC_STORE AS '
	EXEC sp_sqlexec @stmt
END
GO

USE DB_STAT
GO

ALTER PROCEDURE dbo.DB_TC_STORE (@db nvarchar(100), @commt nvarchar(30) = '<unkn>')
AS
	DECLARE @sql nvarchar(2000) -- tu będzie polecenie SQL wstawiajace wynik do tabeli
	,		@id int -- id nadane po wstawieniu rekordu do tabeli DB_STAT 
	,		@tab nvarchar(256) -- nazwa kolejnej tabeli
	,		@cID nvarchar(20) -- skonwertowane @id na tekst
	
	SET @db = LTRIM(RTRIM(@db)) -- usuwamy spacje początkowe i koncowe z nazwy bazy

	/* wstawiamy rekord do tabeli DB_STAT i zapamiętujemy ID jakie nadano nowemu wierszowi */
	INSERT INTO DB_STAT.dbo.DB_STAT (comment, db_nam) VALUES (@commt, @db)
	SET  @id = SCOPE_IDENTITY() -- jakie ID zostało nadane wstawionemu wierszowi
	/* tekstowo ID aby ciągle nie konwetować w pętli */
	SET @cID = RTRIM(LTRIM(STR(@id,20,0)))

	/* przechodzimy do wybranej bazy */
    /* niepotrzebne, nie dziala
	SET @sql = 'USE ' + @db
	EXEC sp_sqlexec @sql
    */

	CREATE TABLE #TC ([table] nvarchar(100) )

	/* w procedurze sp_sqlExec USE jakas_baza tymczasowo przechodzi w ramach polecenia TYLO */
	SET @sql = N'USE [' + @db + N']; INSERT INTO #TC ([table]) '
			+ N' SELECT o.[name] FROM sysobjects o '
			+ N' WHERE (OBJECTPROPERTY(o.[ID], N''isUserTable'') = 1)'
	/* for debug reason not execute but select */
	-- SELECT @sql 
	EXEC sp_sqlexec @sql

	-- SELECT * FROM #TC

	/* kursor po wszystkich tabelach uzytkownika */
	DECLARE CC INSENSITIVE CURSOR FOR 
			SELECT o.[table]
				FROM #TC o
				ORDER BY 1

	OPEN CC -- stoimi przed pierwszym wierszem wyniu
	FETCH NEXT FROM CC INTO @tab -- NEXT ->przejdz do kolejnego wiersza i pobierz dane
								-- do zmiennych pamięciowych

	WHILE (@@FETCH_STATUS = 0)
	BEGIN
		SET @sql = N'USE [' + @db + N']; '
					+ N' INSERT INTO DB_STAT.dbo.DB_RCOUNT (stat_id,[table],rcount) SELECT '
					+ @cID 
					+ ',''' + RTRIM(@tab) + N''', COUNT(*) FROM [' +@db + ']..' + RTRIM(@tab)
		EXEC sp_sqlexec @sql
/*
USE [pwx_db]; 
--INSERT INTO DB_STAT.dbo.DB_RCOUNT (stat_id,[table],rcount) 
 SELECT  'etaty', COUNT(*) FROM [pwx_db]..etaty
*/
		--SELECT @sql as syntax
		/* przechodzimy do następnej tabeli */
		FETCH NEXT FROM CC INTO @tab
	END
	CLOSE CC
	DEALLOCATE CC
GO

USE DB_STAT
GO

--wydmuszka procedury do przechowywania kluczy obcych w bazie

IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = 'DB_TC_STORE_FK')
		AND		(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.DB_TC_STORE_FK AS '
	EXEC sp_sqlexec @stmt
END
GO

USE DB_STAT
GO

-- właściwa procedura do przechowywania kluczy obcych w bazie 

ALTER PROCEDURE dbo.DB_TC_STORE_FK (@db nvarchar(100), @commt nvarchar(30) = '<unkn>')
AS
	DECLARE @sql nvarchar(2000) -- tu będzie polecenie SQL wstawiajace wynik do tabeli
	,		@id int -- id nadane po wstawieniu rekordu do tabeli DB_STAT 
	,		@tab nvarchar(256) -- nazwa kolejneJ tabeli
	,		@cID nvarchar(20) -- skonwertowane @id na tekst

	SET @db = LTRIM(RTRIM(@db)) -- usuwamy spacje początkowe i koncowe z nazwy bazy

	INSERT INTO DB_STAT.dbo.DB_STAT (comment, db_nam) VALUES (@commt, @db)
	SET  @id = SCOPE_IDENTITY() -- jakie ID zostało nadane wstawionemu wierszowi
	/* tekstowo ID aby ciągle nie konwetować w pętli */
	SET @cID = RTRIM(LTRIM(STR(@id,20,0)))

	BEGIN
		SET @sql = N'USE [' + @db + N']; '
					+ N' INSERT INTO DB_STAT.dbo.DB_FK (stat_id,[constraint_name],[delete_table_name],' +
					'[delete_table_column_name],[master_table_name],[master_table_column_name]) SELECT '
					+ @cID 
					+ N', f.name constraint_name, OBJECT_NAME(f.delete_object_id) delete_table_name ' +  
					N',COL_NAME(fc.delete_object_id, fc.delete_column_id) delete_table_column_name ' +
					N',OBJECT_NAME (f.master_object_id) master_table_name ' + 
					N',COL_NAME(fc.master_object_id, fc.master_column_id) master_table_column_name' + 
	
					N' FROM sys.foreign_keys AS f' + 
					N' JOIN sys.foreign_key_columns AS fc' + 
					N' ON f.[object_id] = fc.constraint_object_id' +
					N' ORDER BY f.create_date' 
		
		EXEC sp_sqlexec @sql 
	END
	GO


-- wydmuszka procedury do usuwania kluczy obcych 

IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = 'DB_TC_DROP_FK')
		AND		(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.DB_TC_DROP_FK AS '
	EXEC sp_sqlexec @stmt
END
GO
	
--właściwa procedura do usuwania kluczy obcych 

ALTER PROCEDURE dbo.DB_TC_DROP_FK (@db nvarchar(100), @commt nvarchar(30) = '<unkn>')
AS
	DECLARE @sql nvarchar(2000) -- tu będzie polecenie SQL wstawiajace wynik do tabeli
	,		@id int -- id nadane po wstawieniu rekordu do tabeli DB_STAT 
	,		@tab nvarchar(256) -- nazwa kolejne tabeli
	,		@cID nvarchar(20) -- skonwertowane @id na tekst
	,		@fk_name nvarchar(256) -- nazwa klucza obcego


-- najpierw wywołujemy procedurę do przechowywania istniejących kluczy obcych

	EXEC DB_STAT.dbo.DB_TC_STORE_FK @commt = 'store fk before dropping', @db = @db

	SET @db = LTRIM(RTRIM(@db)) -- usuwamy spacje początkowe i koncowe z nazwy bazy


	/* wstawiamy rekord do tabeli DB_STAT i zapamiętujemy ID jakie nadano nowemu wierszowi */
	INSERT INTO DB_STAT.dbo.DB_STAT (comment, db_nam) VALUES (@commt, @db)
	SET  @id = SCOPE_IDENTITY() -- jakie ID zostało nadane wstawionemu wierszowi
	/* tekstowo ID aby ciągle nie konwetować w pętli */
	SET @id = (SELECT MAX(o.stat_id)
				FROM DB_STAT o
				WHERE o.[db_nam] = @db
				AND EXISTS ( SELECT 1 FROM db_fk f WHERE f.stat_id = o.stat_id))
	SET @cID = RTRIM(LTRIM(STR(@id,20,0)))

-- tworzymy tabele z nazwami tabel w bazie
	CREATE TABLE #TC ([table] nvarchar(256) ) 
-- tworzymy tabele z nazwami fk i nazwami tabeli 
	CREATE	table #FK ([fk_name] nvarchar(256), [fk_table_name] nvarchar(256)) 

	/* w procedurze sp_sqlExec USE jakas_baza tymczasowo przechodzi w ramach polecenia TYLO */
	SET @sql = N'USE [' + @db + N']; INSERT INTO #TC ([table]) '
			+ N' SELECT o.[name] FROM sysobjects o '
			+ N' WHERE (OBJECTPROPERTY(o.[ID], N''isUserTable'') = 1)'
	/* for debug reason not execute but select */
	-- SELECT @sql 
	EXEC sp_sqlexec @sql

	/* kursor po wszystkich tabelach uzytkownika */
	DECLARE CC INSENSITIVE CURSOR FOR 
			SELECT o.[table]
				FROM #TC o
				ORDER BY 1

	OPEN CC -- stoimi przed pierwszym wierszem wyniu
	FETCH NEXT FROM CC INTO @tab -- NEXT ->przejdz do kolejnego wiersza i pobierz dane
								-- do zmiennych pamięciowych

	WHILE (@@FETCH_STATUS = 0)

	BEGIN
		SET @sql = N'USE DB_STAT ' +
		N'INSERT INTO #FK ([fk_name], [fk_table_name]) ' +
		N'SELECT [constraint_name], [delete_table_name] ' +
		N'FROM dbo.DB_FK WHERE [stat_id] = ' + @cID  + N' AND [delete_table_name] = ''' + RTRIM(@tab) + N''''
		
		EXEC sp_sqlexec @sql

		DECLARE CCA INSENSITIVE CURSOR FOR 
		SELECT o.[fk_name]
			FROM #FK o
			ORDER BY 1

			--tworzymy kursor, który po kolei przechodzi po kluczach obcych usuwając je
			OPEN CCA -- stoimi przed pierwszym wierszem
			FETCH NEXT FROM CCA INTO @fk_name -- NEXT ->przejdz do kolejnego wiersza i pobierz dane
								-- do zmiennych pamięciowych
				WHILE (@@FETCH_STATUS = 0)
				BEGIN
						SET @sql = N'USE ' + @db +
						N'; ALTER TABLE ' + @tab + 
						N' DROP CONSTRAINT ' + @fk_name

						EXEC sp_sqlexec @sql

						/* przechodzimy do następnej tabeli */
						FETCH NEXT FROM CCA INTO @fk_name
				END
-- na koniec czyścimy tabele z kluczami obcymi
						TRUNCATE TABLE #FK 
						CLOSE CCA
						DEALLOCATE CCA

		FETCH NEXT FROM CC INTO @tab
	END
	CLOSE CC
	DEALLOCATE CC
GO



-- wydmuszka procedury do odtworzenia kluczy obcych 

IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = 'DB_TC_RECREATE_FK')
		AND		(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.DB_TC_RECREATE_FK AS '
	EXEC sp_sqlexec @stmt
END
GO

--właściwa procedura do odtworzenia kluczy obcych

ALTER PROCEDURE dbo.DB_TC_RECREATE_FK (@db nvarchar(100), @commt nvarchar(30) = '<unkn>', @id int = NULL)
AS
	DECLARE @sql nvarchar(2000) -- tu będzie polecenie SQL wstawiajace wynik do tabeli
	,		@tab nvarchar(256) -- nazwa kolejnej tabeli 
	,		@cID nvarchar(20) -- skonwertowane @id na tekst
	,		@fk_name nvarchar(256) --nazwa fk 
	,		@column_to_delete nvarchar(256) --nazwa kolumny w tabeli usuwanej fk
	,		@table_master nvarchar(256) --nazwa tabeli master fk
	,		@column_master nvarchar(256) --nazwa kolumny w tabeli master fk
	
	SET @db = LTRIM(RTRIM(@db)) -- usuwamy spacje początkowe i koncowe z nazwy bazy

	/* wstawiamy rekord do tabeli DB_STAT i zapamiętujemy ID jakie nadano nowemu wierszowi */
	INSERT INTO DB_STAT.dbo.DB_STAT (comment, db_nam) VALUES (@commt, @db)
	IF @id IS NULL
		BEGIN
			SET @id = (SELECT MAX(o.stat_id)
				FROM DB_STAT o
				WHERE o.[db_nam] = @db
				AND EXISTS ( SELECT 1 FROM db_fk f WHERE f.stat_id = o.stat_id))
		END
	SET @cID = RTRIM(LTRIM(STR(@id,20,0)))


	CREATE TABLE #TC ([table] nvarchar(100) )
	CREATE	table #FK ([constraint_name] nvarchar(100), [delete_table_name] nvarchar(100), [delete_table_column_name] nvarchar(100), 
						[master_table_name]	nvarchar(100), [master_table_column_name] nvarchar(100) )

	/* w procedurze sp_sqlExec USE jakas_baza tymczasowo przechodzi w ramach polecenia TYLO */
	SET @sql = N'USE [' + @db + N']; INSERT INTO #TC ([table]) '
			+ N' SELECT o.[name] FROM sysobjects o '
			+ N' WHERE (OBJECTPROPERTY(o.[ID], N''isUserTable'') = 1)'
	/* for debug reason not execute but select */
	-- SELECT @sql 
	EXEC sp_sqlexec @sql

	/* kursor po wszystkich tabelach uzytkownika */
	DECLARE CC INSENSITIVE CURSOR FOR 
			SELECT o.[table]
				FROM #TC o
				ORDER BY 1

	OPEN CC -- stoimi przed pierwszym wierszem wyniku
	FETCH NEXT FROM CC INTO @tab -- NEXT ->przejdz do kolejnego wiersza i pobierz dane
								-- do zmiennych pamięciowych

	WHILE (@@FETCH_STATUS = 0)
	BEGIN
		SET @sql = N'USE DB_STAT ' +
		N'INSERT INTO #FK ([constraint_name], [delete_table_name], [delete_table_column_name], [master_table_name], [master_table_column_name]) ' +
		N'SELECT [constraint_name], [delete_table_name], [delete_table_column_name], [master_table_name], [master_table_column_name]' +
		N'FROM dbo.DB_FK WHERE [stat_id] = ' + @cID  + N' AND [delete_table_name] = ''' + RTRIM(@tab) + N''''
		
		EXEC sp_sqlexec @sql

		DECLARE CCA INSENSITIVE CURSOR FOR 
		SELECT o.[constraint_name], o.[delete_table_column_name], o.[master_table_name], o.[master_table_column_name]
		FROM #FK o
			ORDER BY 1

			OPEN CCA -- stoimi przed pierwszym wierszem 
			FETCH NEXT FROM CCA INTO @fk_name, @column_to_delete, @table_master, @column_master-- NEXT ->przejdz do kolejnego wiersza i pobierz dane
								-- do zmiennych pamięciowych

				WHILE (@@FETCH_STATUS = 0) 
				BEGIN
						SET @sql = N'USE [' + @db + ']; ALTER TABLE ' + @tab + ' ADD CONSTRAINT ' + @fk_name +
						N' FOREIGN KEY (' + @column_to_delete + ') REFERENCES ' + @table_master + '(' + @column_master + ')'

						EXEC sp_sqlexec @sql

						FETCH NEXT FROM CCA INTO @fk_name, @column_to_delete, @table_master, @column_master
				END
-- na koniec czyścimy tabelę z kluczami obcymi
				TRUNCATE TABLE #FK
				CLOSE CCA
				DEALLOCATE CCA

		FETCH NEXT FROM CC INTO @tab
	END
	CLOSE CC
	DEALLOCATE CC
GO



-- TEST I WYNIKI DZIAŁANIA KODU


/*
zaczynam od testu procedury do przechowywania kluczy

EXEC DB_STAT.dbo.DB_TC_STORE_FK @commt = 'test store fk', @db = N'pwx_db'

wyświetlam wynik:

SELECT * FROM DB_STAT.dbo.DB_FK

stat_id     constraint_name                                                                                      delete_table_name                                                                                    delete_table_column_name                                                                             master_table_name                                                                                    master_table_column_name
----------- ---------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------- ----------------------------------------------------------------------------------------------------
1           fk_miasta__woj                                                                                       miasta                                                                                               kod_woj                                                                                              woj                                                                                                  kod_woj
1           fk_firmy__miasta                                                                                     firmy                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
1           fk_osoby__miasta                                                                                     osoby                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
1           fk_etaty__osoby                                                                                      etaty                                                                                                id_osoby                                                                                             osoby                                                                                                id_osoby
1           fk_etaty__firmy                                                                                      etaty                                                                                                id_firmy                                                                                             firmy                                                                                                nazwa_skr
1           FK_WARTOSCI_CECHY__CECHY                                                                             WARTOSCI_CECH                                                                                        id_CECHY                                                                                             CECHY                                                                                                id_CECHY
1           FK_FIRMY_CECHY__WARTOSCI_CECH                                                                        FIRMY_CECHY                                                                                          id_wartosci                                                                                          WARTOSCI_CECH                                                                                        id_wartosci


SELECT * FROM DB_STAT 

stat_id     db_nam               comment              when                    usr_nam                                                                                              host
----------- -------------------- -------------------- ----------------------- ---------------------------------------------------------------------------------------------------- ----------------------------------------------------------------------------------------------------
1           pwx_db               test store fk        2021-10-23 12:52:17.860 dbo                                                                                                  194291374


następnie testuję procedurę usuwania kluczy:


EXEC DB_STAT.dbo.DB_TC_DROP_FK @commt = 'test drop fk', @db = N'pwx_db'
SELECT * FROM DB_STAT.dbo.DB_FK


stat_id     constraint_name                                                                                      delete_table_name                                                                                    delete_table_column_name                                                                             master_table_name                                                                                    master_table_column_name
----------- ---------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------- ----------------------------------------------------------------------------------------------------
1           fk_miasta__woj                                                                                       miasta                                                                                               kod_woj                                                                                              woj                                                                                                  kod_woj
1           fk_firmy__miasta                                                                                     firmy                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
1           fk_osoby__miasta                                                                                     osoby                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
1           fk_etaty__osoby                                                                                      etaty                                                                                                id_osoby                                                                                             osoby                                                                                                id_osoby
1           fk_etaty__firmy                                                                                      etaty                                                                                                id_firmy                                                                                             firmy                                                                                                nazwa_skr
1           FK_WARTOSCI_CECHY__CECHY                                                                             WARTOSCI_CECH                                                                                        id_CECHY                                                                                             CECHY                                                                                                id_CECHY
1           FK_FIRMY_CECHY__WARTOSCI_CECH                                                                        FIRMY_CECHY                                                                                          id_wartosci                                                                                          WARTOSCI_CECH                                                                                        id_wartosci
2           fk_miasta__woj                                                                                       miasta                                                                                               kod_woj                                                                                              woj                                                                                                  kod_woj
2           fk_firmy__miasta                                                                                     firmy                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
2           fk_osoby__miasta                                                                                     osoby                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
2           fk_etaty__osoby                                                                                      etaty                                                                                                id_osoby                                                                                             osoby                                                                                                id_osoby
2           fk_etaty__firmy                                                                                      etaty                                                                                                id_firmy                                                                                             firmy                                                                                                nazwa_skr
2           FK_WARTOSCI_CECHY__CECHY                                                                             WARTOSCI_CECH                                                                                        id_CECHY                                                                                             CECHY                                                                                                id_CECHY
2           FK_FIRMY_CECHY__WARTOSCI_CECH                                                                        FIRMY_CECHY                                                                                          id_wartosci                                                                                          WARTOSCI_CECH                                                                                        id_wartosci


(tabela zawiera teraz dane pod indeskem 1 jak i pod indeksem 2 poniewaz moja procedura usuwania wywoluje takze procedure zapisywania istniejacych kluczy)


SELECT * FROM DB_STAT


stat_id     db_nam               comment                        when                        usr_nam                                                                                              host
----------- -------------------- ----------------------------- --------------------------  ---------------------------------------------------------------------------------------------------- ----------------------------------------------------------------------------------------------------
1           pwx_db               test store fk                 2021-10-23 12:52:17.860      dbo                                                                                                      194291374
2           pwx_db               test store fk before dropping 2021-10-23 12:55:21.030      dbo                                                                                                      194291374
3           pwx_db               test drop fk                  2021-10-23 12:55:21.087      dbo                                                                                                      194291374




--potem testuję procedurę przywracania kluczy obcych


-- by móc dobrze przetestować funkcje "max_id" musze usunac jakis klucz z indeksem 1
-- mam dwa klucze dla "etaty" dlatego to je usuwam poleceniem:

DELETE FROM DB_STAT.dbo.DB_FK WHERE delete_table_name = 'etaty' AND stat_id = 1 
SELECT * FROM DB_STAT.dbo.DB_FK


stat_id     constraint_name                                                                                      delete_table_name                                                                                    delete_table_column_name                                                                             master_table_name                                                                                    master_table_column_name
----------- ---------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------- ----------------------------------------------------------------------------------------------------
1           fk_miasta__woj                                                                                       miasta                                                                                               kod_woj                                                                                              woj                                                                                                  kod_woj
1           fk_firmy__miasta                                                                                     firmy                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
1           fk_osoby__miasta                                                                                     osoby                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
1           FK_WARTOSCI_CECHY__CECHY                                                                             WARTOSCI_CECH                                                                                        id_CECHY                                                                                             CECHY                                                                                                id_CECHY
1           FK_FIRMY_CECHY__WARTOSCI_CECH                                                                        FIRMY_CECHY                                                                                          id_wartosci                                                                                          WARTOSCI_CECH                                                                                        id_wartosci
2           fk_miasta__woj                                                                                       miasta                                                                                               kod_woj                                                                                              woj                                                                                                  kod_woj
2           fk_firmy__miasta                                                                                     firmy                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
2           fk_osoby__miasta                                                                                     osoby                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
2           fk_etaty__osoby                                                                                      etaty                                                                                                id_osoby                                                                                             osoby                                                                                                id_osoby
2           fk_etaty__firmy                                                                                      etaty                                                                                                id_firmy                                                                                             firmy                                                                                                nazwa_skr
2           FK_WARTOSCI_CECHY__CECHY                                                                             WARTOSCI_CECH                                                                                        id_CECHY                                                                                             CECHY                                                                                                id_CECHY
2           FK_FIRMY_CECHY__WARTOSCI_CECH                                                                        FIRMY_CECHY                                                                                          id_wartosci                                                                                          WARTOSCI_CECH                                                                                        id_wartosci


jak widac nie mam juz w tabeli tych dwoch pozycji (etaty z indeksem 1)


-- teraz zdejmuje i odtwarzam klucze obce:

EXEC DB_STAT.dbo.DB_TC_DROP_FK @commt = 'drop to test max_id', @db = N'pwx_db'
EXEC DB_STAT.dbo.DB_TC_RECREATE_FK @commt = 'test recreate', @db = N'pwx_db'

teraz zapisuje odtworzone klucze obce 
EXEC DB_STAT.dbo.DB_TC_STORE_FK @commt = 'test store recreated', @db = N'pwx_db'

i dokonuje sprawdzenia:

SELECT * FROM DB_STAT.dbo.DB_FK 


stat_id     constraint_name                                                                                      delete_table_name                                                                                    delete_table_column_name                                                                             master_table_name                                                                                    master_table_column_name
----------- ---------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------- ----------------------------------------------------------------------------------------------------
1           fk_miasta__woj                                                                                       miasta                                                                                               kod_woj                                                                                              woj                                                                                                  kod_woj
1           fk_firmy__miasta                                                                                     firmy                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
1           fk_osoby__miasta                                                                                     osoby                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
1           fk_etaty__osoby                                                                                      etaty                                                                                                id_osoby                                                                                             osoby                                                                                                id_osoby
1           fk_etaty__firmy                                                                                      etaty                                                                                                id_firmy                                                                                             firmy                                                                                                nazwa_skr
1           FK_WARTOSCI_CECHY__CECHY                                                                             WARTOSCI_CECH                                                                                        id_CECHY                                                                                             CECHY                                                                                                id_CECHY
1           FK_FIRMY_CECHY__WARTOSCI_CECH                                                                        FIRMY_CECHY                                                                                          id_wartosci                                                                                          WARTOSCI_CECH                                                                                        id_wartosci
2           fk_miasta__woj                                                                                       miasta                                                                                               kod_woj                                                                                              woj                                                                                                  kod_woj
2           fk_firmy__miasta                                                                                     firmy                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
2           fk_osoby__miasta                                                                                     osoby                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
2           fk_etaty__osoby                                                                                      etaty                                                                                                id_osoby                                                                                             osoby                                                                                                id_osoby
2           fk_etaty__firmy                                                                                      etaty                                                                                                id_firmy                                                                                             firmy                                                                                                nazwa_skr
2           FK_WARTOSCI_CECHY__CECHY                                                                             WARTOSCI_CECH                                                                                        id_CECHY                                                                                             CECHY                                                                                                id_CECHY
2           FK_FIRMY_CECHY__WARTOSCI_CECH                                                                        FIRMY_CECHY                                                                                          id_wartosci                                                                                          WARTOSCI_CECH                                                                                        id_wartosci
3           fk_miasta__woj                                                                                       miasta                                                                                               kod_woj                                                                                              woj                                                                                                  kod_woj
3           fk_firmy__miasta                                                                                     firmy                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
3           fk_osoby__miasta                                                                                     osoby                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
3           fk_etaty__osoby                                                                                      etaty                                                                                                id_osoby                                                                                             osoby                                                                                                id_osoby
3           fk_etaty__firmy                                                                                      etaty                                                                                                id_firmy                                                                                             firmy                                                                                                nazwa_skr
3           FK_WARTOSCI_CECHY__CECHY                                                                             WARTOSCI_CECH                                                                                        id_CECHY                                                                                             CECHY                                                                                                id_CECHY
3           FK_FIRMY_CECHY__WARTOSCI_CECH                                                                        FIRMY_CECHY                                                                                          id_wartosci                                                                                          WARTOSCI_CECH                                                                                        id_wartosci
6           fk_miasta__woj                                                                                       miasta                                                                                               kod_woj                                                                                              woj                                                                                                  kod_woj
6           fk_firmy__miasta                                                                                     firmy                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
6           fk_osoby__miasta                                                                                     osoby                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
6           fk_etaty__osoby                                                                                      etaty                                                                                                id_osoby                                                                                             osoby                                                                                                id_osoby
6           fk_etaty__firmy                                                                                      etaty                                                                                                id_firmy                                                                                             firmy                                                                                                nazwa_skr
6           FK_WARTOSCI_CECHY__CECHY                                                                             WARTOSCI_CECH                                                                                        id_CECHY                                                                                             CECHY                                                                                                id_CECHY
6           FK_FIRMY_CECHY__WARTOSCI_CECH                                                                        FIRMY_CECHY                                                                                          id_wartosci                                                                                          WARTOSCI_CECH                                                                                        id_wartosci


jak widzac max_id dziala poprawnie - poniewaz dodano 7 kluczy, czyli tyle ile bylo w max id, a nie 5 jak jest w id = 1


teraz w poleceniu podaje juz id = 1, bo chce sprawdzic czy procedura zadziala poprawnie dla id, gdzie usunelam kilka kluczy 
(czyli sprawdzam czy doda mi te usuniete klucze - nie powinno)

zdejmuje klucze:
EXEC DB_STAT.dbo.DB_TC_DROP_FK @commt = 'test drop fk', @db = N'pwx_db'

i odtwarzam podajac, ze wartosc id ma byc rowna 1:
EXEC DB_STAT.dbo.DB_TC_RECREATE_FK @commt = 'test recreate for id = 1', @db = N'pwx_db', @id=1


zapisuje:
EXEC DB_STAT.dbo.DB_TC_STORE_FK @commt = 'test store for id = 1', @db = N'pwx_db'

i sprawdzam:
SELECT * FROM DB_STAT.dbo.DB_FK 

stat_id     constraint_name                                                                                      delete_table_name                                                                                    delete_table_column_name                                                                             master_table_name                                                                                    master_table_column_name
----------- ---------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------- ----------------------------------------------------------------------------------------------------
1           fk_miasta__woj                                                                                       miasta                                                                                               kod_woj                                                                                              woj                                                                                                  kod_woj
1           fk_firmy__miasta                                                                                     firmy                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
1           fk_osoby__miasta                                                                                     osoby                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
1           fk_etaty__osoby                                                                                      etaty                                                                                                id_osoby                                                                                             osoby                                                                                                id_osoby
1           fk_etaty__firmy                                                                                      etaty                                                                                                id_firmy                                                                                             firmy                                                                                                nazwa_skr
1           FK_WARTOSCI_CECHY__CECHY                                                                             WARTOSCI_CECH                                                                                        id_CECHY                                                                                             CECHY                                                                                                id_CECHY
1           FK_FIRMY_CECHY__WARTOSCI_CECH                                                                        FIRMY_CECHY                                                                                          id_wartosci                                                                                          WARTOSCI_CECH                                                                                        id_wartosci
2           fk_miasta__woj                                                                                       miasta                                                                                               kod_woj                                                                                              woj                                                                                                  kod_woj
2           fk_firmy__miasta                                                                                     firmy                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
2           fk_osoby__miasta                                                                                     osoby                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
2           fk_etaty__osoby                                                                                      etaty                                                                                                id_osoby                                                                                             osoby                                                                                                id_osoby
2           fk_etaty__firmy                                                                                      etaty                                                                                                id_firmy                                                                                             firmy                                                                                                nazwa_skr
2           FK_WARTOSCI_CECHY__CECHY                                                                             WARTOSCI_CECH                                                                                        id_CECHY                                                                                             CECHY                                                                                                id_CECHY
2           FK_FIRMY_CECHY__WARTOSCI_CECH                                                                        FIRMY_CECHY                                                                                          id_wartosci                                                                                          WARTOSCI_CECH                                                                                        id_wartosci
...
10           fk_miasta__woj                                                                                       miasta                                                                                               kod_woj                                                                                              woj                                                                                                  kod_woj
10           fk_firmy__miasta                                                                                     firmy                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
10           fk_osoby__miasta                                                                                     osoby                                                                                                id_miasta                                                                                            miasta                                                                                               id_miasta
10           FK_WARTOSCI_CECHY__CECHY                                                                             WARTOSCI_CECH                                                                                        id_CECHY                                                                                             CECHY                                                                                                id_CECHY
10           FK_FIRMY_CECHY__WARTOSCI_CECH                                                                        FIRMY_CECHY                                                                                          id_wartosci                                                                                          WARTOSCI_CECH                                                                                        id_wartosci


jak widac polecenie zadzialalo tak jak oczekiwalismy - dodalo nam tylko 5 pozycji, nie 7 - czyli dodalo tylko te istniejace dl id =1, usunietych nie dodalo


*/
