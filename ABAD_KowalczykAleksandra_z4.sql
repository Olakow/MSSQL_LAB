-- Aleksandra Kowalczyk 307414


-- Procedura do wyœwietlania kluczy obcych z istniej¹cymi indeksami

CREATE PROCEDURE SHOW_INDEXED_POZ_FK (@db nvarchar(128))
AS
	DECLARE @stmt nvarchar(2048) =  'USE ' + @db + ';
		SELECT i.name AS index_name, f.name AS fk_name, j.name AS table_name, c.name AS column_name
		FROM sys.foreign_keys AS f
		JOIN sys.foreign_key_columns AS fa ON f.object_id = fa.constraint_object_id
		JOIN sys.index_columns AS ia ON fa.parent_object_id = ia.object_id AND fa.parent_column_id = ia.column_id
		JOIN sys.indexes AS i ON ia.object_id = i.object_id AND ia.index_id = i.index_id
		JOIN sys.tables AS j ON i.object_id = j.object_id
		JOIN sys.columns AS c ON j.object_id = c.object_id AND ia.column_id = c.column_id'
	EXEC sp_sqlexec @stmt
GO


-- procedura, która ma parametr @nazwaBazy i dla podanej bazy wyszukuje wszystkie klucze obce
-- wyniki SELECT pokazuja wszystkie klucze obce z indeksami, my chcemy pokazac wszystkie klucze obce


CREATE PROCEDURE DB_INDEX_POZ_FK (@db nvarchar(128))
AS
-- tworze tabele na pozycje z kluczami bez indeksów
	CREATE TABLE #T (master_table_name nvarchar(128), table_name nvarchar(128), column_name nvarchar(128)) 
	DECLARE @stmt nvarchar(2048) 
	SET @db = LTRIM(RTRIM(@db)) 

	SET @stmt = 'USE ' + @db + ';
		INSERT INTO #T
			SELECT OBJECT_NAME(f.referenced_object_id), OBJECT_NAME(f.parent_object_id), COL_NAME(fa.parent_object_id, fa.parent_column_id)
			FROM sys.foreign_keys AS f
			JOIN sys.foreign_key_columns AS fa ON f.object_id = fa.constraint_object_id
			WHERE f.object_id NOT IN (
				SELECT f.object_id
				FROM sys.foreign_keys AS f
				JOIN sys.foreign_key_columns AS fa ON f.object_id = fa.constraint_object_id
				JOIN sys.index_columns AS ia ON fa.parent_object_id = ia.object_id AND fa.parent_column_id = ia.column_id
				JOIN sys.indexes AS i ON ia.object_id = i.object_id AND ia.index_id = i.index_id
			)'
	EXEC sp_sqlexec @stmt

	DECLARE @master_table_name nvarchar(128) 
	DECLARE @table_name nvarchar(128) 
	DECLARE @column_name nvarchar(128) 

	-- tworzê kursor do pobierania kolejnych rekordów 
	DECLARE CONSTRAINT_CURSOR INSENSITIVE CURSOR FOR SELECT master_table_name, table_name, column_name FROM #T

	OPEN CONSTRAINT_CURSOR 
    FETCH NEXT FROM CONSTRAINT_CURSOR INTO @master_table_name, @table_name, @column_name 

	WHILE (@@FETCH_STATUS = 0) 
	BEGIN
		SET @stmt = 'USE ' + @db + '; CREATE INDEX FKI_' + @master_table_name + '_' + @table_name + '_' + @column_name +
						' ON ' + @table_name + '(' + @column_name + ')'
		EXEC sp_sqlexec @stmt
-- Tworzê indeks jeœli nie istnial dla danego klucza obcego

		FETCH NEXT FROM CONSTRAINT_CURSOR INTO @master_table_name, @table_name, @column_name 
	END

	CLOSE CONSTRAINT_CURSOR -- zamykam kursor
	DEALLOCATE CONSTRAINT_CURSOR -- czyszcze kursor
	DROP TABLE #T -- usuwamy tymczasow¹ tabelê
GO



-- SPRAWDZENIE

-- wyœwietlam klucze obce z istniej¹cymi indeksami

EXEC SHOW_INDEXED_POZ_FK  N'DB_Faktury'

-- nastêpnie wywoluje procedure  DB_INDEX_POZ_FK która utworzy mi indeksy jesli nie istanialy dla jakiegos klucza obcego

EXEC DB_INDEX_POZ_FK  N'DB_Faktury'

-- nastepnie ponownie wywoluje procedure SHOW_INDEXED_POZ_FK

EXEC SHOW_INDEXED_POZ_FK  N'DB_Faktury'

-- widzê, ze powstaly brakujace indeksy

-- wywoluje ponownie  DB_INDEX_POZ_FK i potem SHOW_INDEXED_POZ_FK 
-- widzê ze po drugim uruchomieniu nie mam powielonych indeksow

-- polecenie SQL gdzie wymuszam uzycie zrobionego indeksu

-- 1)
SELECT * 
	FROM dbo.Pozycje d  WITH (INDEX(FKI_Faktura_Pozycje_id_faktury)) 
	WHERE d.id_faktury=2

-- 2)

SELECT * 
	FROM dbo.Pozycje d  WITH (INDEX(FKI_Faktura_Pozycje_id_faktury)) 
	WHERE d.id_faktury=5
