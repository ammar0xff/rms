enum ConflictStrategy {
  serverAuthoritative,
  idempotentCreate,
  revisionCheck,
  validateTransition,
  appendOnly,
  trustedValidation,
  requiresReview,
}

class ConflictResolver {
  const ConflictResolver();

  ConflictStrategy strategyFor(String entityType) {
    switch (entityType) {
      case 'menuConfiguration':
      case 'driverAssignment':
      case 'rolePermission':
        return ConflictStrategy.serverAuthoritative;
      case 'orderCreation':
        return ConflictStrategy.idempotentCreate;
      case 'orderItem':
        return ConflictStrategy.revisionCheck;
      case 'kitchenStatus':
        return ConflictStrategy.validateTransition;
      case 'cashPayment':
      case 'driverCollection':
      case 'inventoryMovement':
      case 'supplier':
      case 'purchase':
        return ConflictStrategy.appendOnly;
      case 'settlement':
        return ConflictStrategy.trustedValidation;
      default:
        return ConflictStrategy.requiresReview;
    }
  }
}
