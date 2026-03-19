create or replace procedure reservar_pista(
    arg_dni_usuario        varchar2,
    arg_id_pista           number,
    arg_fecha_ini          date,
    arg_fecha_fin          date,
    arg_incluir_luz        varchar2,
    arg_incluir_limpieza   varchar2
) is
    v_reserva_concurrente  number;
begin
    -- Validación del intervalo
    if arg_fecha_fin < arg_fecha_ini then
        raise_application_error(-20003, 'El intervalo horario no es valido.');
    end if;

    -- Comprobación de existencia de la pista y bloqueo
    begin
        select nombre, tipo_pista, luz_nocturna
        into v_nombre_pista, v_tipo_pista, v_luz_nocturna
        from pistas
        where id_pista = arg_id_pista
        for update; -- For update para hacer un select bloqueante
    exception
        when no_data_found then
            raise_application_error(-20002, 'Pista inexistente.');
    end;

    -- Comprobación de disponibilidad.
    select count(*)
        into v_reserva_concurrente
        from reservas r
    where r.id_pista = arg_id_pista
        and r.fecha_ini < arg_fecha_fin
        and r.fecha_fin > arg_fecha_ini;

    if v_reserva_concurrente > 0 then
        raise_application_error(-20004, 'La pista no esta disponible en ese intervalo.');
    end if;
end;
