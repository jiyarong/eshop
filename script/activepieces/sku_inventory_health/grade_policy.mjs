export const code = async (inputs) => {
  const policy = [inputs.s, inputs.a, inputs.bc, inputs.unknown].find(value => value && typeof value === 'object' && value.shortage_stock !== undefined);
  if (!policy) throw new Error('Grade policy branch did not return a policy');
  return policy;
};
