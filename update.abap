FUNCTION ZHRFM22
  EXPORTING
    E_ERRO TYPE BINPT_FUNC
    E_RETORNO TYPE ZTWS_RETORNO_C
  TABLES
    T_ESTRUTURA LIKE ZLHR_UNIDADES_ORG_PT_EN
    RETURN LIKE BAPIRET2.

  TYPES:
    BEGIN OF ty_response,
      pureid TYPE i,
      uuid   TYPE string,
    END OF ty_response.

  TYPES:
    BEGIN OF ty_get_name,
      first_name TYPE string,
      last_name  TYPE string,
    END OF ty_get_name,

    BEGIN OF ty_get_organization,
      system_name TYPE string,
      uuid        TYPE string,
    END OF ty_get_organization,

    BEGIN OF ty_get_period,
      start_date TYPE string,
    END OF ty_get_period,

    BEGIN OF ty_get_staff_org_ass,
      type_discriminator TYPE string,
      organization       TYPE ty_get_organization,
      period             TYPE ty_get_period,
      primary_association TYPE abap_bool,
    END OF ty_get_staff_org_ass,

    BEGIN OF ty_get_visibility,
      key         TYPE string,
    END OF ty_get_visibility,

    BEGIN OF ty_get_identifier_type,
        uri TYPE string,
    END OF ty_get_identifier_type,

    BEGIN OF ty_get_identifiers,
      id                TYPE string,
      type              TYPE ty_get_identifier_type,
    END OF ty_get_identifiers,

    BEGIN OF ty_get_user,
        uuid TYPE string,
    END OF ty_get_user,

    BEGIN OF ty_get_response,
      name                        TYPE ty_get_name,
      staff_organization_associations TYPE STANDARD TABLE OF ty_get_staff_org_ass WITH EMPTY KEY,
      visibility                  TYPE ty_get_visibility,
      identifiers                 TYPE STANDARD TABLE OF ty_get_identifiers WITH EMPTY KEY,
      user                        TYPE ty_get_user,
      orcid                       TYPE string,
    END OF ty_get_response.


  " Definir a estrutura do JSON
  TYPES: BEGIN OF ty_name,
           first_name TYPE string,
           last_name  TYPE string,
         END OF ty_name,

         BEGIN OF ty_description,
           en_gb TYPE string,
           pt_pt TYPE string,
         END OF ty_description,

         BEGIN OF ty_type,
           uri  TYPE string,
           term TYPE ty_description,
         END OF ty_type,

         BEGIN OF ty_organization,
           system_name TYPE string,
           uuid        TYPE string,
         END OF ty_organization,

         BEGIN OF ty_period,
           start_date TYPE string,
         END OF ty_period,

         BEGIN OF ty_st_org_ass,
           type_discriminator TYPE string,
           organization       TYPE ty_organization,
           period             TYPE ty_period,
         END OF ty_st_org_ass,

         BEGIN OF ty_visibility,
           key         TYPE string,
           description TYPE ty_description,
         END OF ty_visibility,

         BEGIN OF ty_identifiers,
           typediscriminator TYPE string,
           id                TYPE string,
           type_             TYPE ty_type,
         END OF ty_identifiers,

         BEGIN OF ty_data,
           name          TYPE ty_name,
           "student_org_ass TYPE STANDARD TABLE OF ty_st_org_ass WITH EMPTY KEY,
           staff_org_ass TYPE STANDARD TABLE OF ty_st_org_ass WITH EMPTY KEY,
           visibility    TYPE ty_visibility,
           identifiers   TYPE STANDARD TABLE OF ty_identifiers WITH EMPTY KEY,
           user          TYPE ty_organization,
           orcid         TYPE string,
         END OF ty_data.




  " Preencher os dados
  DATA: ls_name          TYPE ty_name,
        ls_organization  TYPE ty_organization,
        ls_period        TYPE ty_period,
        "ls_student_org_ass TYPE ty_st_org_ass,
        ls_staff_org_ass TYPE ty_st_org_ass,
        ls_visibility    TYPE ty_visibility,
        ls_identifiers   TYPE ty_identifiers,
        ls_data          TYPE ty_data,
        ls_zhrtb85       TYPE zhrtb85. "tabela ZHRTB85


* --- passo 2: contar ocorrências de cada par (pernr, uo) ---
* --- Contar ocorrências de cada par (pernr, uo) ---
  TYPES: BEGIN OF ty_pair_counts_line,
           pernr TYPE pa0000-pernr,
           uo    TYPE zhrtb83-uo,
           count TYPE i,
         END OF ty_pair_counts_line.

  DATA: lt_pair_counts TYPE HASHED TABLE OF ty_pair_counts_line
                        WITH UNIQUE KEY pernr uo.

  DATA: ls_pair_key    TYPE ty_pair_counts_line. " Para a chave de leitura
  FIELD-SYMBOLS: <fs_pair_count> LIKE LINE OF lt_pair_counts.

  DATA: t_estrutura_ TYPE TABLE OF zlhr_unidades_org_pt_en.
  FIELD-SYMBOLS: <fs_uo_>             TYPE zlhr_unidades_org_pt_en.


  DATA: lt_response TYPE ty_response.

  " Tratar Json
  DATA: lv_url            TYPE string VALUE '/ws/api/persons',
        lv_api_key        TYPE string VALUE 'e',
        lv_response       TYPE string,
        lv_code           TYPE i,
        lv_reason         TYPE string,

        gv_sobid          TYPE hrp1001-sobid,
        gv_id_uo          TYPE zlhr_unidades_org_pt_en-id_unidade_organizacional,
        gv_id_uo_superior TYPE zlhr_unidades_org_pt_en-id_unidade_organizacional,

        gs_uo             TYPE zlhr_unidades_org_pt_en,
        gv_while          TYPE c LENGTH 1.


  DATA : lo_http_client  TYPE REF TO if_http_client,
         lo_http_request TYPE REF TO if_http_entity.

*  IF sy-sysid EQ 'PR3'.
*    lv_api_key = 'f4455b08-74a7-4c6c-b05a-eeddf4f70b0e'.
*    lv_url = 'https://research.uc.pt/ws/api/organizations'.
*  ENDIF.




* --- Passo 1: Definir estrutura e selecionar dados brutos ---
  SELECT pa0~pernr, pa2~vorna, pa2~nachn ,pa1~persg, pa0~stat2, hrp1~begda, zhr83~uo ,pa1~persk , zhr83~variante, zhr83~uuid
      INTO TABLE  @DATA(lt_dados)
    FROM zhrtb83 AS zhr83
    INNER JOIN hrp1001 AS hrp1
    ON hrp1~objid EQ zhr83~uo
    AND hrp1~sclas EQ 'S'
    AND hrp1~plvar EQ 'PU'
    INNER JOIN hrp1001 AS hrp11
    ON hrp11~objid EQ hrp1~sobid
    AND hrp11~sclas EQ 'P'
    INNER JOIN pa0001 AS pa1
    ON pa1~pernr EQ hrp11~sobid
    INNER JOIN pa0000 AS pa0
    ON pa0~pernr EQ pa1~pernr
    INNER JOIN pa0002 AS pa2
    ON pa2~pernr EQ pa1~pernr
    WHERE   pa0~begda  LE @sy-datum
        AND pa0~endda  GE @sy-datum
        AND pa1~begda  LE @sy-datum
        AND pa1~endda  GE @sy-datum
        AND pa2~begda  LE @sy-datum
        AND pa2~endda  GE @sy-datum
        AND hrp1~begda LE @sy-datum
        AND hrp1~endda GE @sy-datum
        AND hrp11~begda LE @sy-datum
        AND hrp11~endda GE @sy-datum
        AND pa0~stat2 EQ 3.

  IF sy-subrc NE 0.
* Tratar erro na seleção de dados, se necessário
  ENDIF.

* --- Passo 2: Contar ocorrências de cada par (pernr, uo) ---

  LOOP AT lt_dados INTO DATA(ls_data_line).
    ls_pair_key-pernr = ls_data_line-pernr.
    ls_pair_key-uo    = ls_data_line-uo.

    READ TABLE lt_pair_counts FROM ls_pair_key ASSIGNING <fs_pair_count>.
    IF sy-subrc EQ 0.
      " Linha encontrada, incrementar contador diretamente no field symbol
      <fs_pair_count>-count = <fs_pair_count>-count + 1.
    ELSE.
      " Linha não encontrada, preparar uma nova linha e inserir
      DATA ls_new_pair_count TYPE ty_pair_counts_line.
      ls_new_pair_count-pernr = ls_data_line-pernr.
      ls_new_pair_count-uo    = ls_data_line-uo.
      ls_new_pair_count-count = 1.
      INSERT ls_new_pair_count INTO TABLE lt_pair_counts.
    ENDIF.
  ENDLOOP.
* A tabela lt_final_unique_data agora contém o resultado desejado.
  " Ordenar a tabela lt_pair_counts por pernr e uo
  SORT lt_dados BY pernr uo. "ordenar por pernr e uo para evitar duplicados
  DELETE ADJACENT DUPLICATES FROM lt_dados COMPARING pernr uo. "remover duplicados


  SELECT * FROM zhrtb85 INTO TABLE @DATA(lt_zhrtb85).
  SORT lt_zhrtb85 BY pernr uo.


  " Obter a estrutura da UC para ir buscar todas as pessoas que pertencem ao PU com as respectivas UOs com tarefas PURE

  CALL FUNCTION 'ZHRFM23'
    EXPORTING
      i_tarefa    = 'PURE'
    TABLES
      t_estrutura = t_estrutura.

  " obter as pessoas que pertencem ao pu uc com as respetivas uos
  IF lt_dados IS NOT INITIAL. " Importante: Garante que lt_dados não está vazia
    SELECT pa0~pernr, pa2~vorna, pa2~nachn ,pa1~persg, pa0~stat2, hrp11~begda, hrp1~objid, pa1~persk
    INTO TABLE @DATA(lt_dados_2)
    FROM hrp1001 AS hrp1
    INNER JOIN hrp1001 AS hrp11
        ON hrp11~objid EQ hrp1~sobid
    INNER JOIN pa0001 AS pa1
        ON pa1~pernr EQ hrp11~sobid
    INNER JOIN pa0000 AS pa0
        ON pa0~pernr EQ pa1~pernr
    INNER JOIN pa0002 AS pa2
        ON pa2~pernr EQ pa1~pernr
    FOR ALL ENTRIES IN @lt_dados " <--- Esta é a alteração chave
    WHERE pa0~pernr EQ @lt_dados-pernr " <--- E esta
      AND pa0~begda  LE @sy-datum
      AND pa0~endda  GE @sy-datum
      AND pa1~begda  LE @sy-datum
      AND pa1~endda  GE @sy-datum
      AND pa2~begda  LE @sy-datum
      AND pa2~endda  GE @sy-datum
      AND hrp1~begda LE @sy-datum
      AND hrp1~endda GE @sy-datum
      AND hrp11~begda LE @sy-datum
      AND hrp11~endda GE @sy-datum
      AND hrp1~otype EQ 'O'
      AND hrp1~plvar EQ 'UC'
      AND hrp11~sclas EQ 'P'
      AND hrp11~otype EQ 'S'
      AND hrp11~plvar EQ 'UC'
      AND hrp11~rsign EQ 'A'
      AND hrp11~relat EQ '008'

      AND pa0~stat2 EQ 3. "ativos.
  ENDIF.

  "juntar os dados da tabela lt_dados_2 com lt_dados
  LOOP AT lt_dados_2 INTO DATA(ls_dados_2).
    " Se não existir, adicionar à tabela lt_dados
    APPEND ls_dados_2 TO lt_dados.
  ENDLOOP.

  " Ordenar lt_dados por pernr e uo
  SORT lt_dados BY pernr uo.

  "retirar os dados da tabela ZHR85
  LOOP AT lt_dados INTO DATA(ls_dados).
    DATA(index) = sy-tabix.
    " retirar os zeros a esquerda
    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_OUTPUT'
      EXPORTING
        input  = ls_dados-pernr
      IMPORTING
        output = ls_dados-pernr.
    READ TABLE lt_zhrtb85 INTO ls_zhrtb85 WITH KEY pernr = ls_dados-pernr.
    IF sy-subrc EQ 0.
      DELETE lt_dados INDEX index.
    ENDIF.
  ENDLOOP.


  """"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
  " fazer com que lt_dados fique com os dados únicos e passar os apagados para a tabela lt_dados_restantes uo
  " Ordenar lt_dados por pernr e uo
  SORT lt_dados BY pernr. "ordenar por pernr e uo para evitar duplicados
  "guardar os dados antes de remover os duplicados

  DATA(lt_dados_restantes) = lt_dados.

  DELETE ADJACENT DUPLICATES FROM lt_dados COMPARING pernr. "remover duplicados
  " Obter os dados restantes que foram apagados

  """"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

  " Obter a estrutura da UC para ir buscar todas as pessoas que pertencem ao PU com as respetivas UOs com tarefas PURE
  CALL FUNCTION 'ZHRFM23'
    EXPORTING
      i_uo_inicial = 'UC'             " Abreviatura do objeto
      i_variante   = 'UC'
*     i_tarefa     =
    TABLES
      t_estrutura  = t_estrutura_.

  LOOP AT lt_dados INTO ls_dados.
    DATA(lv_person_uuid) = ls_dados-uuid.
    DATA(lv_get_url) = |{ lv_url }/{ lv_person_uuid }|.

    " GET REQUEST
    CALL METHOD cl_http_client=>create_by_url
      EXPORTING
        url                = lv_get_url
      IMPORTING
        client             = lo_http_client
      EXCEPTIONS
        argument_not_found = 1
        plugin_not_active  = 2
        internal_error     = 3
        OTHERS             = 4.

    lo_http_client->request->set_method('GET').
    lo_http_client->request->set_header_field( name = 'api-key' value = lv_api_key ).

    CALL METHOD lo_http_client->send(
      EXCEPTIONS
        http_communication_failure = 1
        http_invalid_state         = 2
        http_processing_failed     = 3
        OTHERS                     = 4
    ).

    IF sy-subrc = 0.
      CALL METHOD lo_http_client->receive(
        EXCEPTIONS
          http_communication_failure = 1
          http_invalid_state         = 2
          http_processing_failed     = 3
          OTHERS                     = 4
      ).
    ENDIF.

    DATA(lv_get_response) = lo_http_client->response->get_cdata( ).
    DATA ls_get_response TYPE ty_get_response.
    /ui2/cl_json=>deserialize(
      EXPORTING
        json = lv_get_response
      CHANGING
        data = ls_get_response
    ).

    CLEAR : ls_name, ls_organization, ls_period, ls_staff_org_ass, ls_visibility, ls_identifiers, ls_data.

    ls_name-first_name = ls_dados-vorna.
    ls_name-last_name = ls_dados-nachn.

    DATA(lv_update_needed) = abap_false.

    IF ls_get_response-name-first_name <> ls_name-first_name OR
       ls_get_response-name-last_name  <> ls_name-last_name OR
       ls_get_response-orcid           <> ls_data-orcid.
      lv_update_needed = abap_true.
    ENDIF.

    " Compare staffOrganizationAssociations
    IF lv_update_needed = abap_false.
      IF lines( ls_get_response-staff_organization_associations ) <> lines( ls_data-staff_org_ass ).
        lv_update_needed = abap_true.
      ELSE.
        LOOP AT ls_get_response-staff_organization_associations INTO DATA(ls_get_staff_org_ass).
          READ TABLE ls_data-staff_org_ass INTO DATA(ls_data_staff_org_ass)
            WITH KEY organization-uuid = ls_get_staff_org_ass-organization-uuid.
          IF sy-subrc <> 0.
            lv_update_needed = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.
    ENDIF.
    CALL FUNCTION 'ZHRFM24'
      EXPORTING
        i_first_name = ls_dados-vorna             " Abreviatura do objeto
        i_last_name  = ls_dados-nachn             " Sobrenome
        i_username   = ls_dados-pernr              " Nº pessoal
      IMPORTING
        e_uuid       = ls_data-user-uuid.
    ls_data-user-system_name = 'User'.


    "ir buscar orcid a IT0105 SUBTY ORCI

    TRY.
        SELECT SINGLE usrid
            INTO ls_data-orcid
        FROM pa0105
        WHERE pernr EQ ls_dados-pernr
         AND subty  EQ 'ORCI'
         AND begda  LE sy-datum
         AND endda  GE sy-datum.
        IF sy-subrc NE 0.
          ls_data-orcid = 'N/A'.
        ENDIF.
      CATCH cx_sql_exception.
        ls_data-orcid = 'N/A'.
    ENDTRY.


    "
    ls_organization-system_name = 'Organization'.
    TRY.


        LOOP AT lt_dados_restantes INTO DATA(ls) WHERE pernr EQ ls_dados-pernr .
          SELECT SINGLE uuid FROM zhrtb83 INTO ls_organization-uuid  WHERE uo  = ls-uo.
          IF sy-subrc NE 0.
            CLEAR gv_id_uo.
            gv_id_uo = ls-uo.
            gv_while = 'X'.
            WHILE gv_while EQ 'X'.
              CLEAR gs_uo.
              READ TABLE t_estrutura_ INTO gs_uo WITH KEY id_unidade_organizacional = gv_id_uo.
              IF sy-subrc EQ 0.
                SELECT SINGLE uuid FROM zhrtb83 INTO ls_organization-uuid  WHERE uo  = gv_id_uo.
                IF sy-subrc NE 0.
                  gv_id_uo = gs_uo-id_uo_superior.
                  gv_while = 'X'.
                ELSE.
                  CLEAR gv_while.
                ENDIF.
              ELSE.
                READ TABLE t_estrutura_ INTO gs_uo WITH KEY id_unidade_organizacional = gs_uo-id_uo_superior.
                IF sy-subrc EQ 0.
                  gv_id_uo = gs_uo-id_uo_superior.
                  gv_while = 'X'.
                ELSE.
                  CLEAR gv_while.
                ENDIF.
              ENDIF.
            ENDWHILE.

          ENDIF.

          " rever a data que tem de ser passada para inicio UO
          CONCATENATE ls_dados-begda+0(4) '-' ls_dados-begda+4(2) '-' ls_dados-begda+6(2) INTO ls_period-start_date.

          "ls_student_org_ass-type_discriminator = 'StudentOrganizationAssociation'.
          ls_staff_org_ass-type_discriminator = 'StaffOrganizationAssociation'.
          ls_staff_org_ass-organization = ls_organization.
          ls_staff_org_ass-period = ls_period.

          APPEND ls_staff_org_ass TO ls_data-staff_org_ass.

        ENDLOOP.

      CATCH cx_sql_exception.
        SELECT SINGLE uuid FROM zhrtb83 INTO ls_organization-uuid .
    ENDTRY.




    ls_visibility-key = 'FREE'.
    ls_visibility-description-en_gb = 'Public - No restriction'.
    ls_visibility-description-pt_pt = '???visibility.FREE???'.

    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_OUTPUT'
      EXPORTING
        input  = ls_dados-pernr
      IMPORTING
        output = ls_dados-pernr.

    CONCATENATE 'uc' ls_dados-pernr '@uc.pt' INTO ls_identifiers-id .
    ls_identifiers-typediscriminator = 'ClassifiedId'.
    ls_identifiers-type_-uri = '/dk/atira/pure/person/personsources/employee'.
    ls_identifiers-type_-term-en_gb = 'Employee ID'.
    ls_identifiers-type_-term-pt_pt = 'ID de funcionário'.



    ls_data-name = ls_name.
    ls_data-visibility = ls_visibility.

    APPEND ls_identifiers TO ls_data-identifiers.





    """"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    """"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    " Converter os dados para JSON
    DATA: lv_json TYPE string.
    CALL METHOD /ui2/cl_json=>serialize
      EXPORTING
        data   = ls_data
      RECEIVING
        r_json = lv_json.


    """"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    " alterar nome das tags json
    REPLACE ALL OCCURRENCES OF 'FIRST_NAME' IN lv_json WITH 'firstName'.
    REPLACE ALL OCCURRENCES OF 'LAST_NAME' IN lv_json WITH 'lastName'.
    REPLACE ALL OCCURRENCES OF 'SYSTEM_NAME' IN lv_json WITH 'systemName'.
    REPLACE ALL OCCURRENCES OF 'NAME' IN lv_json WITH 'name'.
    "REPLACE ALL OCCURRENCES OF 'STUDENT_ORG_ASS' IN lv_json WITH 'studentOrganizationAssociations'.
    REPLACE ALL OCCURRENCES OF 'STAFF_ORG_ASS' IN lv_json WITH 'staffOrganizationAssociations'.
    REPLACE ALL OCCURRENCES OF 'TYPE_DISCRIMINATOR' IN lv_json WITH 'typeDiscriminator'.
    REPLACE ALL OCCURRENCES OF 'ORGANIZATION' IN lv_json WITH 'organization'.
    REPLACE ALL OCCURRENCES OF 'UUID' IN lv_json WITH 'uuid'.
    REPLACE ALL OCCURRENCES OF 'PERIOD' IN lv_json WITH 'period'.
    REPLACE ALL OCCURRENCES OF 'START_DATE' IN lv_json WITH 'startDate'.
    REPLACE ALL OCCURRENCES OF 'VISIBILITY' IN lv_json WITH 'visibility'.
    REPLACE ALL OCCURRENCES OF 'KEY' IN lv_json WITH 'key'.
    REPLACE ALL OCCURRENCES OF 'DESCRIPTION' IN lv_json WITH 'description'.
    REPLACE ALL OCCURRENCES OF 'EN_GB' IN lv_json WITH 'en_GB'.
    REPLACE ALL OCCURRENCES OF 'PT_PT' IN lv_json WITH 'pt_PT'.
    REPLACE ALL OCCURRENCES OF 'USER' IN lv_json WITH 'user'.
    REPLACE ALL OCCURRENCES OF 'ORCID' IN lv_json WITH 'orcid'.
    REPLACE ALL OCCURRENCES OF 'IDENTIFIERS' IN lv_json WITH 'identifiers'.
    REPLACE ALL OCCURRENCES OF 'TYPEDISCRIMINATOR' IN lv_json WITH 'typeDiscriminator'.
    REPLACE ALL OCCURRENCES OF 'TYPE_' IN lv_json WITH 'type'.
    REPLACE ALL OCCURRENCES OF 'URI' IN lv_json WITH 'uri'.
    REPLACE ALL OCCURRENCES OF 'TERM' IN lv_json WITH 'term'.
    REPLACE ALL OCCURRENCES OF 'ID' IN lv_json WITH 'id'.

    "retirar tag orcid se estiver com 'N/A'
    IF ls_data-orcid = 'N/A'.
      REPLACE ALL OCCURRENCES OF ',"orcid":"N/A"' IN lv_json WITH ''.
    ENDIF.

  IF lv_update_needed = abap_true.
    CALL METHOD cl_http_client=>create_by_url
      EXPORTING
        url                = lv_url
      IMPORTING
        client             = lo_http_client
      EXCEPTIONS
        argument_not_found = 1
        plugin_not_active  = 2
        internal_error     = 3
        OTHERS             = 4.


*set http method P
    CALL METHOD lo_http_client->request->set_method('PUT' ).

*set protocol version
    lo_http_client->request->set_version( if_http_request=>co_protocol_version_1_1 ).


    CALL METHOD lo_http_client->request->if_http_entity~set_formfield_encoding
      EXPORTING
        formfield_encoding = cl_http_request=>if_http_entity~co_encoding_raw.

*content type
    CALL METHOD lo_http_client->request->if_http_entity~set_content_type
      EXPORTING
        content_type = if_rest_media_type=>gc_appl_json.

    CALL METHOD lo_http_client->request->set_header_field
      EXPORTING
        name  = 'Accept'
        value = '*/*'.

    CALL METHOD lo_http_client->request->set_header_field
      EXPORTING
        name  = 'Content-Type'
        value = 'application/json'.

    CALL METHOD lo_http_client->request->set_header_field
      EXPORTING
        name  = 'api-key'
        value = lv_api_key.


    CALL METHOD lo_http_client->request->set_form_field
      EXPORTING
        name  = 'size'
        value = '1000'.


    CALL METHOD lo_http_client->request->set_cdata
      EXPORTING
        data = lv_json.



*get data
    CLEAR : lv_response.
    lo_http_request = lo_http_client->request.



    CALL METHOD lo_http_client->send(
      EXPORTING
        timeout                    = 15
      EXCEPTIONS
        http_communication_failure = 1
        http_invalid_state         = 2
        http_processing_failed     = 3
        OTHERS                     = 4 ).


    CALL METHOD lo_http_client->receive(
      EXCEPTIONS
        http_communication_failure = 1
        http_invalid_state         = 2
        http_processing_failed     = 3
        OTHERS                     = 4 ).


*response

    lv_response = lo_http_client->response->get_cdata( ).

    CALL METHOD /ui2/cl_json=>deserialize
      EXPORTING
        json = lv_response
      CHANGING
        data = lt_response.


    "inserir dados na tabela ZHRTB83
    .

    CALL FUNCTION 'ZUCFM03'
      EXPORTING
        i_tipo_mensagem = 'S'                " Campo do sistema: tipo de mensagem
*       i_classe_mensagem = 'ZHR01'          " Campo do sistema ABAP: classe de mensagens
        i_n_mensagem    = '999'                " Campo do sistema ABAP: nº da mensagem
        i_mensagem_1    = CONV syst_msgv( ls_dados-pernr )                " Campo do sistema ABAP: variável da mensagem
        i_mensagem_2    = CONV syst_msgv( lt_response-uuid )               " Campo do sistema ABAP: variável da mensagem
        i_mensagem_3    = CONV syst_msgv( lt_response-pureid )              " Campo do sistema ABAP: variável da mensagem
        i_mensagem_4    = ''                 " Campo do sistema ABAP: variável da mensagem
        i_aplicacao     = 'ZUC'             " Log de aplicação: subobjeto
        i_identificacao = CONV balsubobj( ls_dados-pernr )
        i_objeto_log    = 'ZUC'         " Log de aplicação: nome do objeto (sigla de aplicação)
      IMPORTING
        e_erro          = e_erro              " Tipo de batch input
        e_retorno       = e_retorno.                  " Categ de Tabela de Lista de Resultados Completo Web Services

    ls_zhrtb85-pureid = lt_response-pureid.
    ls_zhrtb85-uuid = lt_response-uuid.
    ls_zhrtb85-pernr = ls_dados-pernr.
    CONCATENATE ls_dados-vorna ls_dados-nachn INTO ls_zhrtb85-name SEPARATED BY ' '.
    ls_zhrtb85-date_update = sy-datum.
    ls_zhrtb85-time_update = sy-uzeit.

    TRY.
        INSERT INTO zhrtb85 VALUES ls_zhrtb85.
      CATCH cx_sy_open_sql_db.
        return-message = 'Erro ao inserir dados na tabela ZHRTB83'.
        APPEND return.
    ENDTRY.

  ENDIF.


  ENDLOOP.
ENDFUNCTION.
